module Fhir
  module ExtractionDefinitions
    module DiagnosticReport
      # category is 0..* CodeableConcept (concept_list_code takes the first). effective[x]
      # is a choice; only effectiveDateTime is extracted to the point column. result and
      # specimen are 0..* references matched via jsonb containment (see SearchDefinitions).
      FIELDS = {
        status: { path: "status" },
        category_code: { path: "category", transform: :concept_list_code },
        code_value: { path: "code", transform: :coding_code },
        code_text: { path: "code", transform: :concept_text },
        subject_reference: { path: "subject.reference" },
        encounter_reference: { path: "encounter.reference" },
        effective_time: { path: "effectiveDateTime", transform: :datetime }
      }.freeze

      TOKENS = {
        "status"   => { path: "status", kind: :code },
        "category" => { path: "category", kind: :codeable_concept_list },
        "code"     => { path: "code", kind: :codeable_concept }
      }.freeze
    end
  end
end
