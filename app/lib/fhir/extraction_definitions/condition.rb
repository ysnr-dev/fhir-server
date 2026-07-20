module Fhir
  module ExtractionDefinitions
    module Condition
      # clinicalStatus / verificationStatus / severity are 0..1 CodeableConcepts with a
      # single fixed CodeSystem, so only the first coding's code is extracted. category
      # is 0..* (concept_list_code takes the first). onset[x] is a choice; only
      # onsetDateTime is extracted to the point column.
      FIELDS = {
        clinical_status: { path: "clinicalStatus", transform: :coding_code },
        verification_status: { path: "verificationStatus", transform: :coding_code },
        category_code: { path: "category", transform: :concept_list_code },
        severity_code: { path: "severity", transform: :coding_code },
        code_value: { path: "code", transform: :coding_code },
        code_text: { path: "code", transform: :concept_text },
        subject_reference: { path: "subject.reference" },
        encounter_reference: { path: "encounter.reference" },
        onset_time: { path: "onsetDateTime", transform: :datetime },
        recorded_time: { path: "recordedDate", transform: :datetime }
      }.freeze
    end
  end
end
