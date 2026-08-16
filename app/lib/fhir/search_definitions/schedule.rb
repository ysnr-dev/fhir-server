module Fhir
  module SearchDefinitions
    module Schedule
      PARAMS = {
        "identifier" => { type: :identifier },
        # 使われなくなった枠は消さずに active=false にするのが FHIR の想定なので、
        # 予約画面は常に active=true で絞る。
        "active" => { type: :boolean, column: :active },
        # Schedule.actor は「誰の / どこの枠か」(担当医・診察室)。1..* なので
        # カラムではなく jsonb containment で突き合わせる。
        # target_type は既定の参照先。Location を明示する場合は
        # actor=Location/{id} のように型付きで渡す。
        "actor" => { type: :reference, multiple: true, jsonb_key: "actor",
                      ref_path: %w[reference], target_type: "Practitioner" },
        # Schedule.planningHorizon は「この枠表が有効な期間」。Encounter.date と同じく
        # eq は期間の包含(重なりではない)で、end が無い場合は無期限として扱う。
        "date" => { type: :datetime, column: :planning_horizon_start,
                     end_column: :planning_horizon_end },
        # 0..* CodeableConcept。1 つの枠表が診療科と診療内容の両方を並べるため、
        # 平坦化した列は持たず resource_tokens だけで突き合わせる
        # (ServiceRequest.category と同じ理由)。
        "service-category" => { type: :token },
        "service-type" => { type: :token },
        "specialty" => { type: :token }
      }.freeze
    end
  end
end
