module Fhir
  module ExtractionDefinitions
    module ServiceRequest
      FIELDS = {
        status: { path: "status" },
        intent: { path: "intent" },
        subject_reference: { path: "subject.reference" },
        encounter_reference: { path: "encounter.reference" },
        requester_reference: { path: "requester.reference" },
        authored_on: { path: "authoredOn", transform: :datetime },
        code: { path: "code", transform: :coding_code },
        code_text: { path: "code", transform: :concept_text }
      }.freeze

      # category は 0..* CodeableConcept。1 件のオーダーがオーダー種別と入外区分の
      # ように複数の概念を並べるため、全 coding を token 行にする(FIELDS に平坦化した
      # 列は持たない。理由は SearchDefinitions::ServiceRequest を参照)。
      TOKENS = {
        "status"   => { path: "status", kind: :code },
        "intent"   => { path: "intent", kind: :code },
        "category" => { path: "category", kind: :codeable_concept_list },
        "code"     => { path: "code", kind: :codeable_concept }
      }.freeze
    end
  end
end
