module Fhir
  module ExtractionDefinitions
    module Composition
      # Composition.type is 1..1 CodeableConcept; category is 0..* (concept_list_code
      # takes the first). author is 0..*/1..* references, matched by jsonb containment
      # (see SearchDefinitions), so it has no extracted column here.
      FIELDS = {
        status: { path: "status" },
        type_code: { path: "type", transform: :coding_code },
        type_text: { path: "type", transform: :concept_text },
        category_code: { path: "category", transform: :concept_list_code },
        subject_reference: { path: "subject.reference" },
        encounter_reference: { path: "encounter.reference" },
        composition_date: { path: "date", transform: :datetime }
      }.freeze

      TOKENS = {
        "status"   => { path: "status", kind: :code },
        "type"     => { path: "type", kind: :codeable_concept },
        "category" => { path: "category", kind: :codeable_concept_list }
      }.freeze
    end
  end
end
