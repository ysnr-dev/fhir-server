module Fhir
  # Maps a FHIR resourceType string to the classes that implement it, so
  # Fhir::Operation (and Bundle transaction/batch processing) can dispatch
  # generically instead of hard-coding a resourceType per call site.
  module ResourceRegistry
    ENTRIES = {
      "Patient" => {
        model: Patient,
        validator: PatientValidator,
        search_params: SearchDefinitions::Patient::PARAMS
      },
      "MedicationRequest" => {
        model: MedicationRequest,
        validator: MedicationRequestValidator,
        search_params: SearchDefinitions::MedicationRequest::PARAMS
      },
      "ServiceRequest" => {
        model: ServiceRequest,
        validator: ServiceRequestValidator,
        search_params: SearchDefinitions::ServiceRequest::PARAMS
      },
      "Practitioner" => {
        model: Practitioner,
        validator: PractitionerValidator,
        search_params: SearchDefinitions::Practitioner::PARAMS
      },
      "Organization" => {
        model: Organization,
        validator: OrganizationValidator,
        search_params: SearchDefinitions::Organization::PARAMS
      }
    }.freeze

    module_function

    def entry_for(resource_type)
      ENTRIES[resource_type]
    end

    def supported?(resource_type)
      ENTRIES.key?(resource_type)
    end

    def types
      ENTRIES.keys
    end
  end
end
