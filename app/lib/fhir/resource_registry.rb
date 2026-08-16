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
        # JP Core splits ImagingStudy into Radiology and Endoscopy profiles, but
        # an entry carries a single profile (Fhir::Meta stamps it on every
        # instance, including past versions rendered via _history/vread). The
        # two are equally strict for this engine -- same 1..1 status/subject,
        # same JP_DICOMModality_VS binding -- so Radiology is registered as the
        # general-purpose one; Endoscopy only narrows reference target types.
        profile: "http://jpfhir.jp/fhir/core/StructureDefinition/JP_ImagingStudy_Radiology"
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
      # ServiceRequest のワークフロー(受付 → 実施 → 完了)を表す。JP Core は Task を
      # プロファイルしていないので、Group / Composition と同じく基底 HL7 定義に載り、
      # 検証は手書きの TaskValidator だけが行う。
      "Task" => {
        model: Task,
        validator: TaskValidator,
        search_params: SearchDefinitions::Task::PARAMS,
        extraction: ExtractionDefinitions::Task::FIELDS,
        token_extraction: ExtractionDefinitions::Task::TOKENS,
        profile: "http://hl7.org/fhir/StructureDefinition/Task"
      },
      # 予約の 3 リソース。Schedule が「担当医・診察室ごとの枠表」、Slot がその中の
      # 個々の時間枠、Appointment が枠を押さえた予約そのもの。Task / Group /
      # Composition と同じく JP Core にプロファイルが無いので基底 HL7 定義に載り、
      # 検証は手書きのバリデータだけが行う。
      "Appointment" => {
        model: Appointment,
        validator: AppointmentValidator,
        search_params: SearchDefinitions::Appointment::PARAMS,
        extraction: ExtractionDefinitions::Appointment::FIELDS,
        token_extraction: ExtractionDefinitions::Appointment::TOKENS,
        profile: "http://hl7.org/fhir/StructureDefinition/Appointment"
      },
      "Schedule" => {
        model: Schedule,
        validator: ScheduleValidator,
        search_params: SearchDefinitions::Schedule::PARAMS,
        extraction: ExtractionDefinitions::Schedule::FIELDS,
        token_extraction: ExtractionDefinitions::Schedule::TOKENS,
        profile: "http://hl7.org/fhir/StructureDefinition/Schedule"
      },
      "Slot" => {
        model: Slot,
        validator: SlotValidator,
        search_params: SearchDefinitions::Slot::PARAMS,
        extraction: ExtractionDefinitions::Slot::FIELDS,
        token_extraction: ExtractionDefinitions::Slot::TOKENS,
        profile: "http://hl7.org/fhir/StructureDefinition/Slot"
      },
      "Practitioner" => {
        model: Practitioner,
        validator: PractitionerValidator,
        search_params: SearchDefinitions::Practitioner::PARAMS,
        extraction: ExtractionDefinitions::Practitioner::FIELDS,
        token_extraction: ExtractionDefinitions::Practitioner::TOKENS,
        extra_identifiers: ExtractionDefinitions::Practitioner::EXTRA_IDENTIFIERS,
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
      # The two JASPEHR (the JApanese Standard Platform for EHRs) profiles --
      # the only entries not on JP Core or a bare HL7 base profile. Their
      # StructureDefinitions are vendored under vendor/jaspehr (rake jaspehr:vendor).
      "Questionnaire" => {
        model: Questionnaire,
        validator: QuestionnaireValidator,
        search_params: SearchDefinitions::Questionnaire::PARAMS,
        extraction: ExtractionDefinitions::Questionnaire::FIELDS,
        token_extraction: ExtractionDefinitions::Questionnaire::TOKENS,
        profile: "http://www.hosp.ncgm.go.jp/JASPEHR/fhir/StructureDefinition/jaspehr-questionnaire"
      },
      "QuestionnaireResponse" => {
        model: QuestionnaireResponse,
        validator: QuestionnaireResponseValidator,
        search_params: SearchDefinitions::QuestionnaireResponse::PARAMS,
        extraction: ExtractionDefinitions::QuestionnaireResponse::FIELDS,
        token_extraction: ExtractionDefinitions::QuestionnaireResponse::TOKENS,
        profile: "http://www.hosp.ncgm.go.jp/JASPEHR/fhir/StructureDefinition/jaspehr-questionnaireresponse"
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
        profile: "http://jpfhir.jp/fhir/core/StructureDefinition/JP_DocumentReference"
      },
      "Binary" => {
        model: Binary,
        validator: BinaryValidator,
        search_params: SearchDefinitions::Binary::PARAMS,
        extraction: ExtractionDefinitions::Binary::FIELDS,
        token_extraction: ExtractionDefinitions::Binary::TOKENS,
        profile: "http://jpfhir.jp/fhir/core/StructureDefinition/JP_Binary"
      },
      "Device" => {
        model: Device,
        validator: DeviceValidator,
        search_params: SearchDefinitions::Device::PARAMS,
        extraction: ExtractionDefinitions::Device::FIELDS,
        token_extraction: ExtractionDefinitions::Device::TOKENS,
        profile: "http://jpfhir.jp/fhir/core/StructureDefinition/JP_Device"
      },
      "RelatedPerson" => {
        model: RelatedPerson,
        validator: RelatedPersonValidator,
        search_params: SearchDefinitions::RelatedPerson::PARAMS,
        extraction: ExtractionDefinitions::RelatedPerson::FIELDS,
        token_extraction: ExtractionDefinitions::RelatedPerson::TOKENS,
        profile: "http://jpfhir.jp/fhir/core/StructureDefinition/JP_RelatedPerson"
      },
      # JP Core defines no Group profile, so this is the one registered type left
      # on a bare HL7 base definition and validated by its hand validator alone.
      # It exists to give Group/$export a cohort to resolve.
      "Group" => {
        model: Group,
        validator: GroupValidator,
        search_params: SearchDefinitions::Group::PARAMS,
        extraction: ExtractionDefinitions::Group::FIELDS,
        token_extraction: ExtractionDefinitions::Group::TOKENS,
        profile: "http://hl7.org/fhir/StructureDefinition/Group"
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
