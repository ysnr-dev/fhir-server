module Fhir
  module ExtractionDefinitions
    module MedicationAdministration
      # effective[x] is a choice of effectiveDateTime (0..1) or effectivePeriod; only
      # the dateTime form is extracted to the point column (effectivePeriod is matched
      # via content when needed).
      FIELDS = {
        status: { path: "status" },
        subject_reference: { path: "subject.reference" },
        context_reference: { path: "context.reference" },
        request_reference: { path: "request.reference" },
        effective_time: { path: "effectiveDateTime", transform: :datetime },
        medication_code: { path: "medicationCodeableConcept", transform: :coding_code },
        medication_text: { path: "medicationCodeableConcept", transform: :concept_text }
      }.freeze
    end
  end
end
