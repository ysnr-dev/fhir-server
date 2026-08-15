module Fhir
  module SearchDefinitions
    module Procedure
      # `date` searches performed[x]; only performedDateTime is extracted.
      PARAMS = {
        "identifier" => { type: :identifier },
        "status"     => { type: :token, column: :status },
        "category"   => { type: :token, column: :category_code },
        "code"       => { type: :token_or_text, token_column: :code_value,
                           text_column: :code_text },
        "subject"    => { type: :reference, column: :subject_reference,
                           target_type: "Patient", aliases: %w[patient] },
        "encounter"  => { type: :reference, column: :encounter_reference, target_type: "Encounter" },
        "date"       => { type: :datetime, column: :performed_time },
        # 0..* references, so matched by jsonb containment rather than a column.
        # Procedure.basedOn は実施の元になった依頼(放射線検査オーダーのヘッダ)を指す。
        # カルテのオーダー表示が「その依頼の実施記録」を引くのに使う。CarePlan は
        # 未実装なので参照先には載せない。
        "based-on"   => { type: :reference, multiple: true, jsonb_key: "basedOn",
                           ref_path: %w[reference], target_type: "ServiceRequest" },
        # Procedure.partOf は 1 回の実施に手技が複数付くとき、2 件目以降を 1 件目
        # (ハブ)にぶら下げる形。R4 では Observation / MedicationAdministration も
        # 参照できるが、束ねる側になるのは Procedure だけなので参照先を絞る。
        "part-of"    => { type: :reference, multiple: true, jsonb_key: "partOf",
                           ref_path: %w[reference], target_type: "Procedure" }
      }.freeze
    end
  end
end
