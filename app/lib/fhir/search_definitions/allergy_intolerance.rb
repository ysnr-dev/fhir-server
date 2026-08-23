module Fhir
  module SearchDefinitions
    module AllergyIntolerance
      # `date` は recordedDate(記録日)、`onset` は onsetDateTime(発症日)。
      # 一覧に出すのは発症日なので、並べ替えも `onset` を使う。
      PARAMS = {
        "identifier"          => { type: :identifier },
        "clinical-status"     => { type: :token, column: :clinical_status },
        "verification-status" => { type: :token, column: :verification_status },
        "type"                => { type: :token, column: :type_code },
        "category"            => { type: :token, column: :category_code },
        "criticality"         => { type: :token, column: :criticality },
        "code"                => { type: :token_or_text, token_column: :code_value,
                                    text_column: :code_text },
        "patient"             => { type: :reference, column: :patient_reference, target_type: "Patient" },
        "date"                => { type: :datetime, column: :recorded_time },
        # onsetDateTime 以外の onset[x] は索引していない(ExtractionDefinitions を参照)。
        "onset"               => { type: :datetime, column: :onset_time }
      }.freeze
    end
  end
end
