module Fhir
  module ExtractionDefinitions
    module Practitioner
      FIELDS = {
        active: { path: "active" },
        gender: { path: "gender" },
        birth_date: { path: "birthDate", transform: :partial_date },
        family: { path: "name", transform: :official_family },
        given: { path: "name", transform: :official_given },
        name_text: { path: "name", transform: :all_name_representations }
      }.freeze

      TOKENS = {
        "gender" => { path: "gender", kind: :code }
      }.freeze

      # JP Core は医籍登録番号を qualification[].identifier に置く。identifier 検索の
      # 索引(resource_identifiers)へトップレベル identifier と併せて取り込むための
      # 追加パス宣言(FhirResourceRecord#sync_identifiers! が参照する)。
      EXTRA_IDENTIFIERS = [
        { array_key: "qualification", identifier_key: "identifier" }
      ].freeze
    end
  end
end
