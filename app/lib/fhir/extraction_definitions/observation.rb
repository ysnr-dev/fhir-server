module Fhir
  module ExtractionDefinitions
    module Observation
      # category is 0..* CodeableConcept, so category_code takes the first concept's
      # first coding code. effective[x] is a choice; the point column takes
      # effectiveDateTime, or the start of effectivePeriod (the onset of an adverse event)
      # so that a period-valued observation is found by `date` too.
      FIELDS = {
        status: { path: "status" },
        category_code: { path: "category", transform: :concept_list_code },
        code_value: { path: "code", transform: :coding_code },
        code_text: { path: "code", transform: :concept_text },
        subject_reference: { path: "subject.reference" },
        encounter_reference: { path: "encounter.reference" },
        effective_time: { path: "effectiveDateTime", fallback: "effectivePeriod.start", transform: :datetime },
        value_quantity: { path: "valueQuantity.value", transform: :decimal }
      }.freeze

      TOKENS = {
        "status"   => { path: "status", kind: :code },
        "category" => { path: "category", kind: :codeable_concept_list },
        "code"     => { path: "code", kind: :codeable_concept }
      }.freeze
    end
  end
end
