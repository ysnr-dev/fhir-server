module Fhir
  module SearchDefinitions
    module ServiceRequest
      # 依頼科(Organization)・入院病棟(Location)を指す fhir-client のローカル拡張。
      # base に置き場が無いためルート直下の extension に入る(Observation:problem と
      # 同じ扱い)。部門ワークリストが「その日の◯◯科のオーダーだけ」を引くのに使う。
      DEPARTMENT_EXTENSION_URL = "http://fhir-client.local/StructureDefinition/order-department".freeze
      WARD_EXTENSION_URL = "http://fhir-client.local/StructureDefinition/order-ward".freeze

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
        # ServiceRequest.occurrenceDateTime(実施予定日時: 撮影日・採取日)。R4 標準の
        # occurrence 検索パラメータ。これまでクライアントは authoredOn に実施日を
        # 重複記載して代用していた。
        "occurrence" => { type: :datetime, column: :occurrence_date_time },
        # 標準外のローカル検索パラメータ(extension[] は他の拡張と配列を共有する
        # ので url も一致条件に入れる)。
        "department" => { type: :reference, multiple: true, jsonb_key: "extension",
                           ref_path: %w[valueReference reference], target_type: "Organization",
                           element_match: { "url" => DEPARTMENT_EXTENSION_URL } },
        "ward"       => { type: :reference, multiple: true, jsonb_key: "extension",
                           ref_path: %w[valueReference reference], target_type: "Location",
                           element_match: { "url" => WARD_EXTENSION_URL } },
        # 0..* references, so matched by jsonb containment rather than a column.
        # ServiceRequest.basedOn は親のオーダーを指す(検体検査オーダーの
        # ヘッダ → パネル → 構成項目)。`based-on:missing=true` で親だけを引ける。
        "based-on"   => { type: :reference, multiple: true, jsonb_key: "basedOn",
                           ref_path: %w[reference], target_type: "ServiceRequest" },
        # ServiceRequest.reasonReference は依頼の理由で、実運用では対象の病名
        # (プロブレム)。カルテを 1 つのプロブレムで縦に読むための絞り込みに使う。
        # 明細の ServiceRequest も親から引き継いだ理由を持つため、ヘッダだけを
        # 引くには `based-on:missing=true` を併用する。R4 の参照先は
        # Condition|Observation|DiagnosticReport|DocumentReference だが、
        # 書かれているのは Condition だけなので既定の参照先はそれに絞る。
        "reason-reference" => { type: :reference, multiple: true, jsonb_key: "reasonReference",
                                 ref_path: %w[reference], target_type: "Condition" }
      }.freeze
    end
  end
end
