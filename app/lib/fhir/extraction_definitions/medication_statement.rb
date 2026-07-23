module Fhir
  module ExtractionDefinitions
    module MedicationStatement
      # effective[x] is a choice of effectiveDateTime (0..1) or effectivePeriod; only
      # the dateTime form is extracted to the point column.
      FIELDS = {
        status: { path: "status" },
        subject_reference: { path: "subject.reference" },
        context_reference: { path: "context.reference" },
        effective_time: { path: "effectiveDateTime", transform: :datetime },
        medication_code: { path: "medicationCodeableConcept", transform: :coding_code },
        medication_text: { path: "medicationCodeableConcept", transform: :concept_text }
      }.freeze

      TOKENS = {
        "status" => { path: "status", kind: :code },
        "code"   => { path: "medicationCodeableConcept", kind: :codeable_concept }
      }.freeze
    end
  end
end
