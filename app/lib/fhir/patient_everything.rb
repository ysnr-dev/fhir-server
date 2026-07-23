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
      compartment_types.flat_map { |type| PatientCompartment.scope_for_patient(type, patient).order(:id) }
    end

    def compartment_types
      candidates = ResourceRegistry.types - %w[Patient]
      return candidates if types.nil?

      unknown = types - ResourceRegistry.types
      raise InvalidType, "Unsupported _type value(s): #{unknown.join(', ')}" if unknown.any?

      candidates & types
    end
  end
end
