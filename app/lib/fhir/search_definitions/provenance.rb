module Fhir
  module SearchDefinitions
    module Provenance
      PARAMS = {
        # Provenance.target は「この活動が生んだ・更新したリソース」で 1..* かつ異種
        # (オーダー 1 件なら ServiceRequest とその MedicationRequest が並ぶ)。列に出せない
        # ので jsonb containment で引く。target_type を ServiceRequest にしてあるのは、
        # 型を省いた id の補完先と、オーダー起点の _has:Provenance:target:... の既定型を
        # 兼ねるため。他の型は "MedicationRequest/xxx" のように型付きで渡せば引ける。
        "target" => { type: :reference, multiple: true, jsonb_key: "target",
                       ref_path: %w[reference], target_type: "ServiceRequest" },
        # R4 の patient は target.where(resolve() is Patient)。target と同じ配列を
        # 参照先の型で切り分ける(Appointment の actor / location と同じ手)。
        # multiple なので Fhir::PatientCompartment の対象にはならない — Provenance は
        # システムスコープのみで読む(Fhir::PatientContext と README を参照)。
        "patient" => { type: :reference, multiple: true, jsonb_key: "target",
                        ref_path: %w[reference], target_type: "Patient" },
        # Provenance.agent[].who。「この医療従事者が関わった記録」を引く。
        "agent" => { type: :reference, multiple: true, jsonb_key: "agent",
                      ref_path: %w[who reference], target_type: "Practitioner" },
        "recorded" => { type: :datetime, column: :recorded },
        # agent.type(author / enterer / verifier …)。オーダー側から
        # _has:Provenance:target:agent-type=verifier で「承認済みのオーダー」を引ける。
        "agent-type" => { type: :token },
        # signature.type(署名の目的コード)。承認の署名を種類で絞る。
        "signature-type" => { type: :token }
        # entity / location / when / agent-role は当面の用途が無いので入れていない。
        # agent-role を足すときは signature-type と同じく配列の中の配列になるので、
        # TokenExtractor に :codeable_concept_list_nested を足す必要がある。
      }.freeze
    end
  end
end
