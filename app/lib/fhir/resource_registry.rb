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
        token_extraction: ExtractionDefinitions::Patient::TOKENS,
        profile: "http://jpfhir.jp/fhir/core/StructureDefinition/JP_Patient"
      },
      "MedicationRequest" => {
        model: MedicationRequest,
        validator: MedicationRequestValidator,
        search_params: SearchDefinitions::MedicationRequest::PARAMS,
        extraction: ExtractionDefinitions::MedicationRequest::FIELDS,
        token_extraction: ExtractionDefinitions::MedicationRequest::TOKENS,
        profile: "http://jpfhir.jp/fhir/core/StructureDefinition/JP_MedicationRequest"
      },
      "Medication" => {
        model: Medication,
        validator: MedicationValidator,
        search_params: SearchDefinitions::Medication::PARAMS,
        extraction: ExtractionDefinitions::Medication::FIELDS,
        token_extraction: ExtractionDefinitions::Medication::TOKENS,
        profile: "http://jpfhir.jp/fhir/core/StructureDefinition/JP_Medication"
      },
      "MedicationDispense" => {
        model: MedicationDispense,
        validator: MedicationDispenseValidator,
        search_params: SearchDefinitions::MedicationDispense::PARAMS,
        extraction: ExtractionDefinitions::MedicationDispense::FIELDS,
        token_extraction: ExtractionDefinitions::MedicationDispense::TOKENS,
        profile: "http://jpfhir.jp/fhir/core/StructureDefinition/JP_MedicationDispense"
      },
      "MedicationAdministration" => {
        model: MedicationAdministration,
        validator: MedicationAdministrationValidator,
        search_params: SearchDefinitions::MedicationAdministration::PARAMS,
        extraction: ExtractionDefinitions::MedicationAdministration::FIELDS,
        token_extraction: ExtractionDefinitions::MedicationAdministration::TOKENS,
        profile: "http://jpfhir.jp/fhir/core/StructureDefinition/JP_MedicationAdministration"
      },
      "MedicationStatement" => {
        model: MedicationStatement,
        validator: MedicationStatementValidator,
        search_params: SearchDefinitions::MedicationStatement::PARAMS,
        extraction: ExtractionDefinitions::MedicationStatement::FIELDS,
        token_extraction: ExtractionDefinitions::MedicationStatement::TOKENS,
        profile: "http://jpfhir.jp/fhir/core/StructureDefinition/JP_MedicationStatement"
      },
      "Observation" => {
        model: Observation,
        validator: ObservationValidator,
        search_params: SearchDefinitions::Observation::PARAMS,
        extraction: ExtractionDefinitions::Observation::FIELDS,
        token_extraction: ExtractionDefinitions::Observation::TOKENS,
        profile: "http://jpfhir.jp/fhir/core/StructureDefinition/JP_Observation_Common"
      },
      "Specimen" => {
        model: Specimen,
        validator: SpecimenValidator,
        search_params: SearchDefinitions::Specimen::PARAMS,
        extraction: ExtractionDefinitions::Specimen::FIELDS,
        token_extraction: ExtractionDefinitions::Specimen::TOKENS,
        profile: "http://jpfhir.jp/fhir/core/StructureDefinition/JP_Specimen_Common"
      },
      "ImagingStudy" => {
        model: ImagingStudy,
        validator: ImagingStudyValidator,
        search_params: SearchDefinitions::ImagingStudy::PARAMS,
        extraction: ExtractionDefinitions::ImagingStudy::FIELDS,
        token_extraction: ExtractionDefinitions::ImagingStudy::TOKENS,
        profile: "http://hl7.org/fhir/StructureDefinition/ImagingStudy"
      },
      "DiagnosticReport" => {
        model: DiagnosticReport,
        validator: DiagnosticReportValidator,
        search_params: SearchDefinitions::DiagnosticReport::PARAMS,
        extraction: ExtractionDefinitions::DiagnosticReport::FIELDS,
        token_extraction: ExtractionDefinitions::DiagnosticReport::TOKENS,
        profile: "http://jpfhir.jp/fhir/core/StructureDefinition/JP_DiagnosticReport_Common"
      },
      "ServiceRequest" => {
        model: ServiceRequest,
        validator: ServiceRequestValidator,
        search_params: SearchDefinitions::ServiceRequest::PARAMS,
        extraction: ExtractionDefinitions::ServiceRequest::FIELDS,
        token_extraction: ExtractionDefinitions::ServiceRequest::TOKENS,
        profile: "http://jpfhir.jp/fhir/core/StructureDefinition/JP_ServiceRequest_Common"
      },
      "Practitioner" => {
        model: Practitioner,
        validator: PractitionerValidator,
        search_params: SearchDefinitions::Practitioner::PARAMS,
        extraction: ExtractionDefinitions::Practitioner::FIELDS,
        token_extraction: ExtractionDefinitions::Practitioner::TOKENS,
        profile: "http://jpfhir.jp/fhir/core/StructureDefinition/JP_Practitioner"
      },
      "Organization" => {
        model: Organization,
        validator: OrganizationValidator,
        search_params: SearchDefinitions::Organization::PARAMS,
        extraction: ExtractionDefinitions::Organization::FIELDS,
        token_extraction: ExtractionDefinitions::Organization::TOKENS,
        profile: "http://jpfhir.jp/fhir/core/StructureDefinition/JP_Organization"
      },
      "PractitionerRole" => {
        model: PractitionerRole,
        validator: PractitionerRoleValidator,
        search_params: SearchDefinitions::PractitionerRole::PARAMS,
        extraction: ExtractionDefinitions::PractitionerRole::FIELDS,
        token_extraction: ExtractionDefinitions::PractitionerRole::TOKENS,
        profile: "http://jpfhir.jp/fhir/core/StructureDefinition/JP_PractitionerRole"
      },
      "Encounter" => {
        model: Encounter,
        validator: EncounterValidator,
        search_params: SearchDefinitions::Encounter::PARAMS,
        extraction: ExtractionDefinitions::Encounter::FIELDS,
        token_extraction: ExtractionDefinitions::Encounter::TOKENS,
        profile: "http://jpfhir.jp/fhir/core/StructureDefinition/JP_Encounter"
      },
      "Location" => {
        model: Location,
        validator: LocationValidator,
        search_params: SearchDefinitions::Location::PARAMS,
        extraction: ExtractionDefinitions::Location::FIELDS,
        token_extraction: ExtractionDefinitions::Location::TOKENS,
        profile: "http://jpfhir.jp/fhir/core/StructureDefinition/JP_Location"
      },
      "Condition" => {
        model: Condition,
        validator: ConditionValidator,
        search_params: SearchDefinitions::Condition::PARAMS,
        extraction: ExtractionDefinitions::Condition::FIELDS,
        token_extraction: ExtractionDefinitions::Condition::TOKENS,
        profile: "http://jpfhir.jp/fhir/core/StructureDefinition/JP_Condition"
      },
      "AllergyIntolerance" => {
        model: AllergyIntolerance,
        validator: AllergyIntoleranceValidator,
        search_params: SearchDefinitions::AllergyIntolerance::PARAMS,
        extraction: ExtractionDefinitions::AllergyIntolerance::FIELDS,
        token_extraction: ExtractionDefinitions::AllergyIntolerance::TOKENS,
        profile: "http://jpfhir.jp/fhir/core/StructureDefinition/JP_AllergyIntolerance"
      },
      "Procedure" => {
        model: Procedure,
        validator: ProcedureValidator,
        search_params: SearchDefinitions::Procedure::PARAMS,
        extraction: ExtractionDefinitions::Procedure::FIELDS,
        token_extraction: ExtractionDefinitions::Procedure::TOKENS,
        profile: "http://jpfhir.jp/fhir/core/StructureDefinition/JP_Procedure"
      },
      "Immunization" => {
        model: Immunization,
        validator: ImmunizationValidator,
        search_params: SearchDefinitions::Immunization::PARAMS,
        extraction: ExtractionDefinitions::Immunization::FIELDS,
        token_extraction: ExtractionDefinitions::Immunization::TOKENS,
        profile: "http://jpfhir.jp/fhir/core/StructureDefinition/JP_Immunization"
      },
      "Coverage" => {
        model: InsuranceCoverage,
        validator: CoverageValidator,
        search_params: SearchDefinitions::Coverage::PARAMS,
        extraction: ExtractionDefinitions::Coverage::FIELDS,
        token_extraction: ExtractionDefinitions::Coverage::TOKENS,
        profile: "http://jpfhir.jp/fhir/core/StructureDefinition/JP_Coverage"
      },
      "Composition" => {
        model: Composition,
        validator: CompositionValidator,
        search_params: SearchDefinitions::Composition::PARAMS,
        extraction: ExtractionDefinitions::Composition::FIELDS,
        token_extraction: ExtractionDefinitions::Composition::TOKENS,
        profile: "http://hl7.org/fhir/StructureDefinition/Composition"
      },
      "DocumentReference" => {
        model: DocumentReference,
        validator: DocumentReferenceValidator,
        search_params: SearchDefinitions::DocumentReference::PARAMS,
        extraction: ExtractionDefinitions::DocumentReference::FIELDS,
        token_extraction: ExtractionDefinitions::DocumentReference::TOKENS,
        profile: "http://hl7.org/fhir/StructureDefinition/DocumentReference"
      },
      "Binary" => {
        model: Binary,
        validator: BinaryValidator,
        search_params: SearchDefinitions::Binary::PARAMS,
        extraction: ExtractionDefinitions::Binary::FIELDS,
        token_extraction: ExtractionDefinitions::Binary::TOKENS,
        profile: "http://hl7.org/fhir/StructureDefinition/Binary"
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
