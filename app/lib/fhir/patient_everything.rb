module Fhir
  # GET /Patient/:id/$everything -- collects the patient compartment: the
  # Patient itself plus every registered resource that references it. Membership
  # is derived from the search definitions (any :reference param whose
  # target_type is Patient), so newly registered resource types join the
  # compartment automatically.
  #
  # Supported operation parameters:
  #   _type  - comma-separated resource types to include (the subject Patient is
  #            always returned; an unknown type is the caller's error)
  #   _since - only resources whose meta.lastUpdated is at or after the instant
  #            (applies to the Patient too -- the incremental-sync use case)
  #
  # The result is returned whole, as a self-contained searchset Bundle without
  # paging -- acceptable at this server's data sizes; add paging alongside
  # $export if volumes grow.
  class PatientEverything
    class InvalidType < StandardError; end

    def self.call(patient:, base_url:, types: nil, since: nil)
      new(patient, base_url, types, since).call
    end

    def initialize(patient, base_url, types, since)
      @patient = patient
      @base_url = base_url
      @types = types
      @since = since
    end

    def call
      records = ([patient] + compartment_records).select { |record| since.nil? || record.last_updated >= since }

      {
        "resourceType" => "Bundle",
        "type" => "searchset",
        "total" => records.size,
        "entry" => records.map do |record|
          {
            "fullUrl" => "#{base_url}/#{record.content['resourceType']}/#{record.id}",
            "resource" => Fhir::Meta.apply(record.content, version_id: record.version_id, last_updated: record.last_updated),
            "search" => { "mode" => "match" }
          }
        end
      }
    end

    private

    attr_reader :patient, :base_url, :types, :since

    def compartment_records
      reference = "Patient/#{patient.id}"

      compartment_types.flat_map do |type|
        entry = ResourceRegistry.entry_for(type)
        columns = patient_reference_columns(entry)
        next [] if columns.empty?

        scope = entry[:model].where(deleted: false)
        scope.where(columns.map { |column| "#{column} = ?" }.join(" OR "), *([reference] * columns.size)).order(:id)
      end
    end

    def compartment_types
      candidates = ResourceRegistry.types - %w[Patient]
      return candidates if types.nil?

      unknown = types - ResourceRegistry.types
      raise InvalidType, "Unsupported _type value(s): #{unknown.join(', ')}" if unknown.any?

      candidates & types
    end

    # Every reference search param targeting Patient is an extracted column in
    # the current registry (no multiple:true Patient references exist), so
    # compartment membership is a plain indexed column match.
    def patient_reference_columns(entry)
      entry[:search_params].values
                           .select { |definition| definition[:type] == :reference && definition[:target_type] == "Patient" && !definition[:multiple] }
                           .map { |definition| definition[:column] }
                           .uniq
    end
  end
end
