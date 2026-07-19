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

    def self.create(resource_type, payload, id: nil)
      new(resource_type).create(payload, id: id)
    end

    def self.read(resource_type, id)
      new(resource_type).read(id)
    end

    def self.update(resource_type, id, payload, if_match: nil)
      new(resource_type).update(id, payload, if_match: if_match)
    end

    def self.delete(resource_type, id)
      new(resource_type).delete(id)
    end

    def self.search(resource_type, params, base_url:)
      new(resource_type).search(params, base_url: base_url)
    end

    def initialize(resource_type)
      @resource_type = resource_type
      @entry = ResourceRegistry.entry_for(resource_type)
    end

    def create(payload, id: nil)
      return unsupported_type_result unless entry
      return resource_type_mismatch_result(payload) unless resource_type_matches?(payload)

      validation = entry[:validator].call(payload)
      return validation_result(validation) unless validation.valid?

      record = id ? entry[:repository].create(payload, id: id) : entry[:repository].create(payload)
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
        updated = entry[:repository].update(record, payload, if_match_version: if_match)
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

    def delete(id)
      return unsupported_type_result unless entry

      record = entry[:model].find_by(id: id)
      return not_found_result(id) unless record
      return Result.new(status: :no_content, resource_id: id) if record.deleted?

      entry[:repository].delete(record)
      Result.new(status: :no_content, resource_id: id)
    end

    def search(params, base_url:)
      return unsupported_type_result unless entry

      result = entry[:search].call(params)
      bundle = BundleBuilder.searchset(result: result, base_url: base_url, query_params: params, resource_type: resource_type)
      Result.new(status: :ok, resource: bundle)
    end

    private

    attr_reader :resource_type, :entry

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
