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

    # http://hl7.org/fhir/ValueSet/location-status (required)
    LOCATION_STATUS = %w[active suspended inactive].freeze
    # http://hl7.org/fhir/ValueSet/location-mode (required)
    LOCATION_MODE = %w[instance kind].freeze

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
