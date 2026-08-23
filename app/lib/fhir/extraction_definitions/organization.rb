module Fhir
  module ExtractionDefinitions
    module Organization
      FIELDS = {
        active: { path: "active" },
        name: { path: "name" },
        partof_reference: { path: "partOf.reference" },
        # _sort=identifier 用の平坦列(検索は resource_identifiers で行う)。
        # 診療科(type=dept)の一覧を診療科コード順に返すために使う。
        identifier_value: { path: "identifier", transform: :first_identifier_value }
      }.freeze

      TOKENS = {
        # Organization.type(施設/診療科の別など)。0..* CodeableConcept なので
        # 全 coding を token 行にする。
        "type" => { path: "type", kind: :codeable_concept_list }
      }.freeze
    end
  end
end
