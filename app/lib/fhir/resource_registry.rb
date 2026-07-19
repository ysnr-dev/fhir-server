module Fhir
  # Maps a FHIR resourceType string to the classes that implement it, so
  # Fhir::Operation (and Bundle transaction/batch processing) can dispatch
  # generically instead of hard-coding a resourceType per call site.
  module ResourceRegistry
    ENTRIES = {
      "Patient" => {
        model: Patient,
        validator: PatientValidator,
        repository: PatientRepository,
        search: PatientSearch
      },
      "MedicationRequest" => {
        model: MedicationRequest,
        validator: MedicationRequestValidator,
        repository: MedicationRequestRepository,
        search: MedicationRequestSearch
      },
      "ServiceRequest" => {
        model: ServiceRequest,
        validator: ServiceRequestValidator,
        repository: ServiceRequestRepository,
        search: ServiceRequestSearch
      },
      "Practitioner" => {
        model: Practitioner,
        validator: PractitionerValidator,
        repository: PractitionerRepository,
        search: PractitionerSearch
      },
      "Organization" => {
        model: Organization,
        validator: OrganizationValidator,
        repository: OrganizationRepository,
        search: OrganizationSearch
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
