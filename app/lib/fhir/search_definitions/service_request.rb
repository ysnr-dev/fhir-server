module Fhir
  module SearchDefinitions
    module ServiceRequest
      PARAMS = {
        "identifier" => { type: :identifier },
        "status"     => { type: :token, column: :status },
        "intent"     => { type: :token, column: :intent },
        # ServiceRequest.category はオーダーの種別(処方・検体検査・放射線検査…)を
        # 分ける唯一の手掛かりで、部門ごとのワークリストが「その日の放射線検査だけ」を
        # 引くのに使う。0..* CodeableConcept で意味のある coding が先頭とは限らないため、
        # 平坦化した列は持たず resource_tokens だけで突き合わせる(Observation の
        # category_code のように先頭を採る列は、並び順に依存して取りこぼす)。
        "category"   => { type: :token },
        "subject"    => { type: :reference, column: :subject_reference,
                           target_type: "Patient", aliases: %w[patient] },
        "encounter"  => { type: :reference, column: :encounter_reference, target_type: "Encounter" },
        "requester"  => { type: :reference, column: :requester_reference, target_type: "Practitioner" },
        "code"       => { type: :token_or_text, token_column: :code,
                           text_column: :code_text },
        "authoredon" => { type: :datetime, column: :authored_on },
        # 0..* references, so matched by jsonb containment rather than a column.
        # ServiceRequest.basedOn は親のオーダーを指す(検体検査オーダーの
        # ヘッダ → パネル → 構成項目)。`based-on:missing=true` で親だけを引ける。
        "based-on"   => { type: :reference, multiple: true, jsonb_key: "basedOn",
                           ref_path: %w[reference], target_type: "ServiceRequest" }
      }.freeze
    end
  end
end
