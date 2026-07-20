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
      "Medication" => {
        model: Medication,
        validator: MedicationValidator,
        search_params: SearchDefinitions::Medication::PARAMS,
        extraction: ExtractionDefinitions::Medication::FIELDS,
        profile: "http://jpfhir.jp/fhir/core/StructureDefinition/JP_Medication"
      },
      "MedicationDispense" => {
        model: MedicationDispense,
        validator: MedicationDispenseValidator,
        search_params: SearchDefinitions::MedicationDispense::PARAMS,
        extraction: ExtractionDefinitions::MedicationDispense::FIELDS,
        profile: "http://jpfhir.jp/fhir/core/StructureDefinition/JP_MedicationDispense"
      },
      "MedicationAdministration" => {
        model: MedicationAdministration,
        validator: MedicationAdministrationValidator,
        search_params: SearchDefinitions::MedicationAdministration::PARAMS,
        extraction: ExtractionDefinitions::MedicationAdministration::FIELDS,
        profile: "http://jpfhir.jp/fhir/core/StructureDefinition/JP_MedicationAdministration"
      },
      "MedicationStatement" => {
        model: MedicationStatement,
        validator: MedicationStatementValidator,
        search_params: SearchDefinitions::MedicationStatement::PARAMS,
        extraction: ExtractionDefinitions::MedicationStatement::FIELDS,
        profile: "http://jpfhir.jp/fhir/core/StructureDefinition/JP_MedicationStatement"
      },
      "Observation" => {
        model: Observation,
        validator: ObservationValidator,
        search_params: SearchDefinitions::Observation::PARAMS,
        extraction: ExtractionDefinitions::Observation::FIELDS,
        profile: "http://jpfhir.jp/fhir/core/StructureDefinition/JP_Observation_Common"
      },
      "Specimen" => {
        model: Specimen,
        validator: SpecimenValidator,
        search_params: SearchDefinitions::Specimen::PARAMS,
        extraction: ExtractionDefinitions::Specimen::FIELDS,
        profile: "http://jpfhir.jp/fhir/core/StructureDefinition/JP_Specimen"
      },
      "ImagingStudy" => {
        model: ImagingStudy,
        validator: ImagingStudyValidator,
        search_params: SearchDefinitions::ImagingStudy::PARAMS,
        extraction: ExtractionDefinitions::ImagingStudy::FIELDS,
        profile: "http://hl7.org/fhir/StructureDefinition/ImagingStudy"
      },
      "DiagnosticReport" => {
        model: DiagnosticReport,
        validator: DiagnosticReportValidator,
        search_params: SearchDefinitions::DiagnosticReport::PARAMS,
        extraction: ExtractionDefinitions::DiagnosticReport::FIELDS,
        profile: "http://jpfhir.jp/fhir/core/StructureDefinition/JP_DiagnosticReport_Common"
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
