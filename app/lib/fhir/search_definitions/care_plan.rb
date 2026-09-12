module Fhir
  module SearchDefinitions
    module CarePlan
      # `subject` は Patient を指す 0..1 の参照で、`patient` はその別名(Condition と
      # 同じ扱い)。target_type が Patient の単一列参照なので、CarePlan は
      # Fhir::PatientCompartment に自動で入り、Patient/$everything に載る。
      #
      # クリニカルパス(ePath)は 1 回の適用を CarePlan の木で表す -- 適用(親)の下に
      # 病日、その下に OAT ユニット、さらに観察項目が並び、子孫はいずれも partOf に
      # 祖先すべてを並べる。そのため
      #   part-of:missing=true            -> 適用そのもの(木の根)だけ
      #   part-of=CarePlan/{適用の id}    -> その適用の木全体
      # で引ける(ServiceRequest のヘッダを based-on:missing=true で引くのと同じ形)。
      #
      # 標準のうち care-team / performer / replaces / activity-* は書き手が無く、
      # 引く当ても無いので定義しない(必要になったら 1 行足す)。
      PARAMS = {
        "identifier" => { type: :identifier },
        "status"     => { type: :token, column: :status },
        "intent"     => { type: :token, column: :intent },
        # CarePlan.category は 0..* CodeableConcept。意味のある coding が先頭とは
        # 限らないので平坦化した列は持たず resource_tokens だけで突き合わせる
        # (ServiceRequest.category と同じ)。
        "category"   => { type: :token },
        "subject"    => { type: :reference, column: :subject_reference,
                           target_type: "Patient", aliases: %w[patient] },
        "encounter"  => { type: :reference, column: :encounter_reference, target_type: "Encounter" },
        # eq は仕様どおりの包含(検索区間が period を完全に含む)。period.end が
        # NULL なら「まだ継続中」を意味する(Encounter.date と同じ)。
        "date"       => { type: :datetime, column: :period_start, end_column: :period_end },
        # 0..* references, so matched by jsonb containment rather than a column.
        "part-of"    => { type: :reference, multiple: true, jsonb_key: "partOf",
                           ref_path: %w[reference], target_type: "CarePlan" },
        # CarePlan.goal は達成目標(Goal)への参照。計画の検索に
        # _include=CarePlan:goal を添えると、目標と評価まで 1 リクエストで揃う
        # (Goal から計画への逆参照は R4 に無いので、辿る向きはこちらだけ)。
        "goal"       => { type: :reference, multiple: true, jsonb_key: "goal",
                           ref_path: %w[reference], target_type: "Goal" },
        # 元にした定義。FHIR 上の PlanDefinition を指すなら canonical、FHIR の外の
        # 定義(このサーバーの外にあるパスマスタなど)を指すなら uri。
        "instantiates-canonical" => { type: :uri, column: :instantiates_canonical },
        "instantiates-uri"       => { type: :uri, column: :instantiates_uri }
      }.freeze
    end
  end
end
