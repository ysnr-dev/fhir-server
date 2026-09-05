module Fhir
  module ExtractionDefinitions
    module Flag
      # status は primitive code。category は 0..* CodeableConcept
      # (concept_list_code が先頭を取る)。code は 1..1 CodeableConcept で、
      # コード検索とテキスト検索の両方に使う。
      FIELDS = {
        status: { path: "status" },
        category_code: { path: "category", transform: :concept_list_code },
        code_value: { path: "code", transform: :coding_code },
        code_text: { path: "code", transform: :concept_text },
        subject_reference: { path: "subject.reference" },
        encounter_reference: { path: "encounter.reference" },
        author_reference: { path: "author.reference" },
        period_start: { path: "period.start", transform: :datetime },
        period_end: { path: "period.end", transform: :datetime }
      }.freeze

      # Token search sources (resource_tokens), keyed by canonical search-param name.
      TOKENS = {
        "status"   => { path: "status", kind: :code },
        "category" => { path: "category", kind: :codeable_concept_list },
        "code"     => { path: "code", kind: :codeable_concept }
      }.freeze
    end
  end
end
