module Fhir
  module ExtractionDefinitions
    module Observation
      # category is 0..* CodeableConcept, so category_code takes the first concept's
      # first coding code. effective[x] is a choice; only effectiveDateTime is
      # extracted to the point column (effectivePeriod is matched via content when needed).
      FIELDS = {
        status: { path: "status" },
        category_code: { path: "category", transform: :concept_list_code },
        code_value: { path: "code", transform: :coding_code },
        code_text: { path: "code", transform: :concept_text },
        subject_reference: { path: "subject.reference" },
        encounter_reference: { path: "encounter.reference" },
        effective_time: { path: "effectiveDateTime", transform: :datetime }
      }.freeze
    end
  end
end
