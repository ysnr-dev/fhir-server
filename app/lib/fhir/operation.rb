module Fhir
  # Executes a single FHIR interaction (create/read/update/delete/search) against
  # whichever resource type is registered in Fhir::ResourceRegistry, independent
  # of HTTP. Used by both the per-resource controllers and Bundle transaction/batch
  # processing so the two share identical validation/persistence behavior.
  class Operation
    Result = Struct.new(:status, :resource, :location_path, :version_id, :outcome, :resource_id, keyword_init: true) do
      def success?
        Rack::Utils::SYMBOL_TO_STATUS_CODE[status].to_i < 400
      end
    end

    def self.create(resource_type, payload, id: nil, if_none_exist: nil)
      new(resource_type).create(payload, id: id, if_none_exist: if_none_exist)
    end

    def self.read(resource_type, id)
      new(resource_type).read(id)
    end

    def self.update(resource_type, id, payload, if_match: nil)
      new(resource_type).update(id, payload, if_match: if_match)
    end

    def self.conditional_update(resource_type, criteria, payload)
      new(resource_type).conditional_update(criteria, payload)
    end

    def self.delete(resource_type, id)
      new(resource_type).delete(id)
    end

    def self.search(resource_type, query_string, base_url:)
      new(resource_type).search(query_string, base_url: base_url)
    end

    def initialize(resource_type)
      @resource_type = resource_type
      @entry = ResourceRegistry.entry_for(resource_type)
    end

    def create(payload, id: nil, if_none_exist: nil)
      return unsupported_type_result unless entry
      return resource_type_mismatch_result(payload) unless resource_type_matches?(payload)

      if if_none_exist.present?
        match = ConditionalMatch.call(resource_type, if_none_exist)
        return conditional_failure_result(match) if %i[invalid multiple].include?(match.outcome)

        # Exactly one match: conditional create is a no-op that returns the
        # existing resource (200 OK, not 201).
        if match.outcome == :one
          record = match.record
          return Result.new(status: :ok, resource: resource_for(record), version_id: record.version_id, resource_id: record.id)
        end
      end

      validation = entry[:validator].call(payload)
      return validation_result(validation) unless validation.valid?

      record = id ? repository.create(payload, id: id) : repository.create(payload)
      Result.new(
        status: :created,
        resource: resource_for(record),
        location_path: "#{resource_type}/#{record.id}/_history/#{record.version_id}",
        version_id: record.version_id,
        resource_id: record.id
      )
    end

    def read(id)
      return unsupported_type_result unless entry

      record = entry[:model].find_by(id: id)
      return not_found_result(id) unless record
      return gone_result(id) if record.deleted?

      Result.new(status: :ok, resource: resource_for(record), version_id: record.version_id, resource_id: record.id)
    end

    def update(id, payload, if_match: nil)
      return unsupported_type_result unless entry

      record = entry[:model].find_by(id: id)
      return not_found_result(id) unless record
      return resource_type_mismatch_result(payload) unless resource_type_matches?(payload)

      validation = entry[:validator].call(payload)
      return validation_result(validation) unless validation.valid?

      begin
        updated = repository.update(record, payload, if_match_version: if_match)
      rescue StandardError => e
        raise unless e.respond_to?(:current_version_id)

        return Result.new(
          status: :precondition_failed,
          outcome: Fhir::OperationOutcome.single(
            severity: "error",
            code: "conflict",
            diagnostics: "If-Match versionId does not match current versionId #{e.current_version_id}"
          )
        )
      end

      Result.new(status: :ok, resource: resource_for(updated), version_id: updated.version_id, resource_id: updated.id)
    end

    # PUT /{type}?{criteria}: updates the single resource matching the criteria
    # (200), creates a new one when nothing matches (201, server-assigned id),
    # and fails with 412 when the criteria are ambiguous.
    def conditional_update(criteria, payload)
      return unsupported_type_result unless entry
      return resource_type_mismatch_result(payload) unless resource_type_matches?(payload)

      match = ConditionalMatch.call(resource_type, criteria)
      case match.outcome
      when :invalid, :multiple
        conditional_failure_result(match)
      when :none
        create(payload)
      else
        # Per spec, a payload id that contradicts the matched resource is an error.
        if payload["id"].present? && payload["id"] != match.record.id
          return Result.new(
            status: :bad_request,
            outcome: Fhir::OperationOutcome.single(
              severity: "error",
              code: "invalid",
              diagnostics: "Resource id '#{payload['id']}' does not match the resource selected by the " \
                           "conditional criteria (#{resource_type}/#{match.record.id})"
            )
          )
        end

        update(match.record.id, payload)
      end
    end

    def delete(id)
      return unsupported_type_result unless entry

      record = entry[:model].find_by(id: id)
      return not_found_result(id) unless record
      return Result.new(status: :no_content, resource_id: id) if record.deleted?

      repository.delete(record)
      Result.new(status: :no_content, resource_id: id)
    end

    def search(query_string, base_url:)
      return unsupported_type_result unless entry

      search_params = SearchParams.parse(query_string.to_s)
      result = Search.call(resource_type, search_params)
      included = IncludeResolver.call(resource_type: resource_type, records: result.records, search_params: search_params)
      bundle = BundleBuilder.searchset(result: result, base_url: base_url, search_params: search_params, resource_type: resource_type, included: included)
      Result.new(status: :ok, resource: bundle)
    end

    private

    attr_reader :resource_type, :entry

    def repository
      @repository ||= Repository.new(resource_type)
    end

    def resource_type_matches?(payload)
      payload.is_a?(Hash) && payload["resourceType"] == resource_type
    end

    def resource_for(record)
      Fhir::Meta.apply(record.content, version_id: record.version_id, last_updated: record.last_updated)
    end

    def not_found_result(id)
      Result.new(
        status: :not_found,
        outcome: Fhir::OperationOutcome.single(
          severity: "error", code: "not-found", diagnostics: "#{resource_type}/#{id} not found"
        )
      )
    end

    def gone_result(id)
      Result.new(
        status: :gone,
        outcome: Fhir::OperationOutcome.single(
          severity: "error", code: "deleted", diagnostics: "#{resource_type}/#{id} has been deleted"
        )
      )
    end

    def resource_type_mismatch_result(payload)
      Result.new(
        status: :bad_request,
        outcome: Fhir::OperationOutcome.single(
          severity: "error",
          code: "structure",
          diagnostics: "resourceType must be '#{resource_type}', got '#{payload.is_a?(Hash) ? payload['resourceType'] : payload.inspect}'"
        )
      )
    end

    def validation_result(validation)
      Result.new(status: :unprocessable_entity, outcome: Fhir::OperationOutcome.build(validation.issues))
    end

    # Maps a failed ConditionalMatch to its HTTP result: unusable criteria are
    # the client's error (400); ambiguous criteria are 412 Precondition Failed.
    def conditional_failure_result(match)
      invalid = match.outcome == :invalid
      Result.new(
        status: invalid ? :bad_request : :precondition_failed,
        outcome: Fhir::OperationOutcome.single(
          severity: "error",
          code: invalid ? "invalid" : "multiple-matches",
          diagnostics: match.diagnostics
        )
      )
    end

    def unsupported_type_result
      Result.new(
        status: :bad_request,
        outcome: Fhir::OperationOutcome.single(
          severity: "error", code: "not-supported", diagnostics: "Unsupported resourceType '#{resource_type}'"
        )
      )
    end
  end
end
