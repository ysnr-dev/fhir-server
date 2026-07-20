module Fhir
  module ExtractionDefinitions
    module MedicationDispense
      FIELDS = {
        status: { path: "status" },
        subject_reference: { path: "subject.reference" },
        context_reference: { path: "context.reference" },
        when_handed_over: { path: "whenHandedOver", transform: :datetime },
        medication_code: { path: "medicationCodeableConcept", transform: :coding_code },
        medication_text: { path: "medicationCodeableConcept", transform: :concept_text }
      }.freeze
    end
  end
end
