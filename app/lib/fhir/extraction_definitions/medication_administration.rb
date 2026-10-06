module Fhir
  module ExtractionDefinitions
    module MedicationAdministration
      # ロット番号を持つ fhir-client のローカル拡張(ルート直下 extension、valueString)。
      # 薬剤(特定生物由来製品など)と輸血の製剤番号。どちらも lot-number 検索で引く。
      LOT_NUMBER_EXTENSION_URLS = %w[
        http://fhir-client.local/StructureDefinition/medication-lot-number
        http://fhir-client.local/StructureDefinition/transfusion-lot-number
      ].freeze

      # effective[x] is a choice of effectiveDateTime (0..1) or effectivePeriod; only
      # the dateTime form is extracted to the point column (effectivePeriod is matched
      # via content when needed).
      FIELDS = {
        status: { path: "status" },
        subject_reference: { path: "subject.reference" },
        context_reference: { path: "context.reference" },
        request_reference: { path: "request.reference" },
        effective_time: { path: "effectiveDateTime", transform: :datetime },
        medication_code: { path: "medicationCodeableConcept", transform: :coding_code },
        medication_text: { path: "medicationCodeableConcept", transform: :concept_text },
        lot_number: { path: "extension", transform: :extension_string, with: LOT_NUMBER_EXTENSION_URLS }
      }.freeze

      TOKENS = {
        "status" => { path: "status", kind: :code },
        "code"   => { path: "medicationCodeableConcept", kind: :codeable_concept }
      }.freeze
    end
  end
end
