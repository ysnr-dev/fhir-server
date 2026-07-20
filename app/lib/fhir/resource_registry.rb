module Fhir
  # Maps a FHIR resourceType string to the classes that implement it, so
  # Fhir::Operation (and Bundle transaction/batch processing) can dispatch
  # generically instead of hard-coding a resourceType per call site.
  module ResourceRegistry
    ENTRIES = {
      "Patient" => {
        model: Patient,
        validator: PatientValidator,
        search_params: SearchDefinitions::Patient::PARAMS,
        extraction: ExtractionDefinitions::Patient::FIELDS,
        profile: "http://jpfhir.jp/fhir/core/StructureDefinition/JP_Patient"
      },
      "MedicationRequest" => {
        model: MedicationRequest,
        validator: MedicationRequestValidator,
        search_params: SearchDefinitions::MedicationRequest::PARAMS,
        extraction: ExtractionDefinitions::MedicationRequest::FIELDS,
        profile: "http://jpfhir.jp/fhir/core/StructureDefinition/JP_MedicationRequest"
      },
      "ServiceRequest" => {
        model: ServiceRequest,
        validator: ServiceRequestValidator,
        search_params: SearchDefinitions::ServiceRequest::PARAMS,
        extraction: ExtractionDefinitions::ServiceRequest::FIELDS,
        profile: "http://jpfhir.jp/fhir/core/StructureDefinition/JP_ServiceRequest_Common"
      },
      "Practitioner" => {
        model: Practitioner,
        validator: PractitionerValidator,
        search_params: SearchDefinitions::Practitioner::PARAMS,
        extraction: ExtractionDefinitions::Practitioner::FIELDS,
        profile: "http://jpfhir.jp/fhir/core/StructureDefinition/JP_Practitioner"
      },
      "Organization" => {
        model: Organization,
        validator: OrganizationValidator,
        search_params: SearchDefinitions::Organization::PARAMS,
        extraction: ExtractionDefinitions::Organization::FIELDS,
        profile: "http://jpfhir.jp/fhir/core/StructureDefinition/JP_Organization"
      },
      "PractitionerRole" => {
        model: PractitionerRole,
        validator: PractitionerRoleValidator,
        search_params: SearchDefinitions::PractitionerRole::PARAMS,
        extraction: ExtractionDefinitions::PractitionerRole::FIELDS,
        profile: "http://jpfhir.jp/fhir/core/StructureDefinition/JP_PractitionerRole"
      },
      "Encounter" => {
        model: Encounter,
        validator: EncounterValidator,
        search_params: SearchDefinitions::Encounter::PARAMS,
        extraction: ExtractionDefinitions::Encounter::FIELDS,
        profile: "http://jpfhir.jp/fhir/core/StructureDefinition/JP_Encounter"
      },
      "Location" => {
        model: Location,
        validator: LocationValidator,
        search_params: SearchDefinitions::Location::PARAMS,
        extraction: ExtractionDefinitions::Location::FIELDS,
        profile: "http://jpfhir.jp/fhir/core/StructureDefinition/JP_Location"
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
