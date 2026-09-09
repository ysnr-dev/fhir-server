module Fhir
  module ExtractionDefinitions
    module ServiceRequest
      # オーダーの終了日を持つ fhir-client のローカル拡張(ルート直下 extension)。
      # 継続的な指示(看護指示・食事・リハビリ・栄養指導)は occurrenceDateTime を開始日
      # にし、終了は occurrencePeriod ではなくこの拡張で表す(occurrence[x] は choice で
      # 開始日の dateTime と併用できないため)。値は valueDate か valueDateTime。
      ORDER_END_EXTENSION_URLS = %w[
        http://fhir-client.local/StructureDefinition/nursing-order-end
        http://fhir-client.local/StructureDefinition/meal-order-end
        http://fhir-client.local/StructureDefinition/rehab-order-end
        http://fhir-client.local/StructureDefinition/nutrition-guidance-order-end
      ].freeze

      FIELDS = {
        status: { path: "status" },
        intent: { path: "intent" },
        subject_reference: { path: "subject.reference" },
        encounter_reference: { path: "encounter.reference" },
        requester_reference: { path: "requester.reference" },
        authored_on: { path: "authoredOn", transform: :datetime },
        # 実施予定日時(撮影日・採取日)。オーダー発行日(authoredOn)と別に検索する。
        occurrence_date_time: { path: "occurrenceDateTime", transform: :datetime },
        # オーダーの終了(上記のローカル拡張)。order-period 検索の end_column。
        order_end: { path: "extension", transform: :extension_datetime, with: ORDER_END_EXTENSION_URLS },
        code: { path: "code", transform: :coding_code },
        code_text: { path: "code", transform: :concept_text }
      }.freeze

      # category は 0..* CodeableConcept。1 件のオーダーがオーダー種別と入外区分の
      # ように複数の概念を並べるため、全 coding を token 行にする(FIELDS に平坦化した
      # 列は持たない。理由は SearchDefinitions::ServiceRequest を参照)。
      TOKENS = {
        "status"      => { path: "status", kind: :code },
        "intent"      => { path: "intent", kind: :code },
        "category"    => { path: "category", kind: :codeable_concept_list },
        "code"        => { path: "code", kind: :codeable_concept },
        # requisition は 0..1 Identifier。system|value の token として引く。
        "requisition" => { path: "requisition", kind: :identifier }
      }.freeze
    end
  end
end
