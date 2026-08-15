module Fhir
  module SearchDefinitions
    module Observation
      PARAMS = {
        "identifier" => { type: :identifier },
        "status"     => { type: :token, column: :status },
        "category"   => { type: :token, column: :category_code },
        "code"       => { type: :token_or_text, token_column: :code_value,
                           text_column: :code_text },
        "subject"    => { type: :reference, column: :subject_reference,
                           target_type: "Patient", aliases: %w[patient] },
        "encounter"  => { type: :reference, column: :encounter_reference, target_type: "Encounter" },
        "date"       => { type: :datetime, column: :effective_time },
        # 0..* references, so matched by jsonb containment rather than a column.
        # Observation.partOf は「どの実施に伴って測った値か」を指す(放射線検査の
        # 被曝線量)。R4 の参照先は投薬・撮影など複数あるが、実際に束ねているのは
        # Procedure なので参照先を絞る。
        "part-of"    => { type: :reference, multiple: true, jsonb_key: "partOf",
                           ref_path: %w[reference], target_type: "Procedure" },
        # Observation.derivedFrom は「この値の元になった記録」。テンプレート回答
        # (QuestionnaireResponse)から抽出した Observation が回答を指すので、回答を
        # 更新・削除する側が「前回この回答から作った Observation」を引くのに使う。
        # R4 の参照先は多いが、抽出元として書かれるのは回答だけなので絞る。
        "derived-from" => { type: :reference, multiple: true, jsonb_key: "derivedFrom",
                             ref_path: %w[reference], target_type: "QuestionnaireResponse" }
      }.freeze
    end
  end
end
