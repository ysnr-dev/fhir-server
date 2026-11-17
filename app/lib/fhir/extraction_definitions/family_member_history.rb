module Fhir
  module ExtractionDefinitions
    module FamilyMemberHistory
      # status は primitive code。relationship / sex は 0..1 の CodeableConcept。
      # condition は 0..* の backbone で、code_text には全 condition の code の
      # テキストを連結して入れる(どの病名でも `code` のテキスト検索に掛かるように)。
      FIELDS = {
        status: { path: "status" },
        relationship_code: { path: "relationship", transform: :coding_code },
        sex_code: { path: "sex", transform: :coding_code },
        code_text: { path: "condition", transform: :nested_concept_text, with: "code" },
        patient_reference: { path: "patient.reference" },
        recorded_time: { path: "date", transform: :datetime }
      }.freeze

      # Token search sources (resource_tokens), keyed by canonical search-param name.
      # "condition.code" は配列を 1 段踏み越えて、全 condition の code を集める。
      TOKENS = {
        "status"       => { path: "status", kind: :code },
        "relationship" => { path: "relationship", kind: :codeable_concept },
        "sex"          => { path: "sex", kind: :codeable_concept },
        "code"         => { path: "condition.code", kind: :codeable_concept_list }
      }.freeze
    end
  end
end
