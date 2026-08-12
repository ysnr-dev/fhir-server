module Fhir
  # Single source of truth for FHIR / JP Core terminology used during validation:
  # ValueSet enum bindings, identifier system URLs / OIDs, and type codes. Keyed by
  # the element (or system) they belong to, so the same ValueSet is never redefined
  # per validator. As more JP Core resources are added, their bindings are declared
  # here rather than inline in each validator.
  module Terminology
    # --- ValueSets (enum bindings) -----------------------------------------

    # http://hl7.org/fhir/ValueSet/administrative-gender (required)
    GENDER = %w[male female other unknown].freeze

    # http://hl7.org/fhir/ValueSet/medicationrequest-status (required)
    MEDICATION_REQUEST_STATUS = %w[active on-hold cancelled completed entered-in-error stopped draft unknown].freeze
    # http://hl7.org/fhir/ValueSet/medicationrequest-intent (required)
    MEDICATION_REQUEST_INTENT = %w[proposal plan order original-order reflex-order filler-order instance-order option].freeze

    # http://hl7.org/fhir/ValueSet/medication-status (required)
    MEDICATION_STATUS = %w[active inactive entered-in-error].freeze
    # http://hl7.org/fhir/ValueSet/medicationdispense-status (required)
    MEDICATION_DISPENSE_STATUS = %w[preparation in-progress cancelled on-hold completed entered-in-error stopped declined unknown].freeze
    # http://hl7.org/fhir/ValueSet/medication-admin-status (required)
    MEDICATION_ADMINISTRATION_STATUS = %w[in-progress not-done on-hold completed entered-in-error stopped unknown].freeze
    # http://hl7.org/fhir/ValueSet/medication-statement-status (required)
    MEDICATION_STATEMENT_STATUS = %w[active completed entered-in-error intended stopped on-hold unknown not-taken].freeze

    # http://hl7.org/fhir/ValueSet/request-status (required)
    SERVICE_REQUEST_STATUS = %w[draft active on-hold revoked completed entered-in-error unknown].freeze
    # http://hl7.org/fhir/ValueSet/request-intent (required)
    SERVICE_REQUEST_INTENT = %w[proposal plan directive order original-order reflex-order filler-order instance-order option].freeze

    # http://hl7.org/fhir/ValueSet/task-status (required)
    TASK_STATUS = %w[draft requested received accepted rejected ready cancelled
                     in-progress on-hold failed completed entered-in-error].freeze
    # http://hl7.org/fhir/ValueSet/task-intent (required) -- request-intent plus
    # the Task-only "unknown" code.
    TASK_INTENT = %w[unknown proposal plan order original-order reflex-order
                     filler-order instance-order option].freeze
    # http://hl7.org/fhir/ValueSet/request-priority (required) -- Task.priority
    REQUEST_PRIORITY = %w[routine urgent asap stat].freeze

    # http://hl7.org/fhir/ValueSet/encounter-status (required)
    ENCOUNTER_STATUS = %w[planned arrived triaged in-progress onleave finished cancelled entered-in-error unknown].freeze

    # http://hl7.org/fhir/ValueSet/observation-status (required)
    OBSERVATION_STATUS = %w[registered preliminary final amended corrected cancelled entered-in-error unknown].freeze

    # http://hl7.org/fhir/ValueSet/specimen-status (required)
    SPECIMEN_STATUS = %w[available unavailable unsatisfactory entered-in-error].freeze
    # http://hl7.org/fhir/ValueSet/imagingstudy-status (required)
    IMAGING_STUDY_STATUS = %w[registered available cancelled entered-in-error unknown].freeze
    # http://hl7.org/fhir/ValueSet/diagnostic-report-status (required)
    DIAGNOSTIC_REPORT_STATUS = %w[registered partial preliminary final amended corrected appended cancelled entered-in-error unknown].freeze

    # http://hl7.org/fhir/ValueSet/document-reference-status (required)
    DOCUMENT_REFERENCE_STATUS = %w[current superseded entered-in-error].freeze
    # http://hl7.org/fhir/ValueSet/composition-status (required) -- DocumentReference.docStatus
    COMPOSITION_STATUS = %w[preliminary final amended entered-in-error].freeze

    # http://hl7.org/fhir/ValueSet/location-status (required)
    LOCATION_STATUS = %w[active suspended inactive].freeze
    # http://hl7.org/fhir/ValueSet/location-mode (required)
    LOCATION_MODE = %w[instance kind].freeze

    # http://hl7.org/fhir/ValueSet/condition-clinical (required)
    CONDITION_CLINICAL_STATUS = %w[active recurrence relapse inactive remission resolved].freeze
    # http://hl7.org/fhir/ValueSet/condition-ver-status (required)
    CONDITION_VERIFICATION_STATUS = %w[unconfirmed provisional differential confirmed refuted entered-in-error].freeze

    # http://hl7.org/fhir/ValueSet/allergyintolerance-clinical (required)
    ALLERGY_CLINICAL_STATUS = %w[active inactive resolved].freeze
    # http://hl7.org/fhir/ValueSet/allergyintolerance-verification (required)
    ALLERGY_VERIFICATION_STATUS = %w[unconfirmed confirmed refuted entered-in-error].freeze
    # http://hl7.org/fhir/ValueSet/allergy-intolerance-type (required)
    ALLERGY_TYPE = %w[allergy intolerance].freeze
    # http://hl7.org/fhir/ValueSet/allergy-intolerance-category (required)
    ALLERGY_CATEGORY = %w[food medication environment biologic].freeze
    # http://hl7.org/fhir/ValueSet/allergy-intolerance-criticality (required)
    ALLERGY_CRITICALITY = %w[low high unable-to-assess].freeze

    # http://hl7.org/fhir/ValueSet/event-status (required) -- Procedure.status
    EVENT_STATUS = %w[preparation in-progress not-done on-hold stopped completed entered-in-error unknown].freeze

    # http://hl7.org/fhir/ValueSet/immunization-status (required)
    IMMUNIZATION_STATUS = %w[completed entered-in-error not-done].freeze

    # http://hl7.org/fhir/ValueSet/fm-status (required) -- Coverage.status
    FINANCIAL_RESOURCE_STATUS = %w[active cancelled draft entered-in-error].freeze

    # http://hl7.org/fhir/ValueSet/device-status (required)
    DEVICE_STATUS = %w[active inactive entered-in-error unknown].freeze

    # http://hl7.org/fhir/ValueSet/group-type (required)
    GROUP_TYPE = %w[person animal practitioner device medication substance].freeze

    # http://hl7.org/fhir/ValueSet/publication-status (required) -- Questionnaire.status
    QUESTIONNAIRE_STATUS = %w[draft active retired unknown].freeze
    # http://hl7.org/fhir/ValueSet/questionnaire-answers-status (required)
    QUESTIONNAIRE_RESPONSE_STATUS = %w[in-progress completed amended entered-in-error stopped].freeze

    # --- JASPEHR (the JApanese Standard Platform for EHRs) IG v1.0.0 ---------

    # .../ValueSet/questionnaire-item-type-Jaspehr (required) -- the base
    # http://hl7.org/fhir/item-type codes minus boolean / url / open-choice /
    # attachment / reference / quantity. Enumerated here rather than expanded
    # from the vendored ValueSet because the base CodeSystem it includes ships
    # with hl7.fhir.r4.core, which this server does not vendor.
    QUESTIONNAIRE_ITEM_TYPE_JASPEHR =
      %w[group display decimal integer date dateTime time string text choice].freeze

    # jsp-4 / jsp-5 / jsr-1: half-width alphanumerics plus a fixed symbol set.
    JASPEHR_TOKEN_PATTERN = %r{\A[A-Za-z0-9\-.!\#%/:;?@_~]{1,255}\z}
    # jsp-5 additionally caps Questionnaire.name.
    JASPEHR_NAME_MAX_LENGTH = 15
    # valid-value-institutionNumberExtension: 2-digit prefecture + 1-digit fee
    # schedule class (1|2|3) + 7-digit institution code.
    JASPEHR_INSTITUTION_NUMBER_PATTERN = /\A[0-4][0-9][1-3][0-9]{7}\z/
    # QuestionnaireResponse.identifier: 保険医療機関番号 ^ 患者ID ^ 報告単位ID.
    JASPEHR_QR_IDENTIFIER_PARTS = 3

    # --- Identifier systems / OIDs (JP Core) --------------------------------

    # JP Core Patient medical record number (院内カルテ番号) identifier system.
    MEDICAL_RECORD_NUMBER_OID = "urn:oid:1.2.392.100495.20.3.51".freeze
    # JP Core MedicationRequest RP (処方) group number slice system.
    MEDICATION_RP_NUMBER_SYSTEM = "http://jpfhir.jp/fhir/core/mhlw/IdSystem/Medication-RPGroupNumber".freeze
    # JP Core MedicationRequest order-within-RP slice system.
    MEDICATION_ORDER_IN_RP_SYSTEM = "http://jpfhir.jp/fhir/core/mhlw/IdSystem/MedicationAdministrationIndex".freeze

    # --- Type codes ---------------------------------------------------------

    # Identifier.type coding code for a medical record number (v2-0203).
    MEDICAL_RECORD_TYPE_CODE = "MR".freeze
  end
end
