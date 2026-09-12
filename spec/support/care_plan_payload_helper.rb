module CarePlanPayloadHelper
  # クリニカルパス(ePath)の適用 1 件ぶんに相当する最小の計画。木の根なので partOf は
  # 持たず、子(病日・OAT ユニット・観察項目)は part_of: を渡して作る。
  def valid_care_plan_payload(subject_id:, **overrides)
    {
      "resourceType" => "CarePlan",
      "identifier" => [{ "system" => "http://example.org/care-plan", "value" => "CP1" }],
      "status" => "active",
      "intent" => "plan",
      "title" => "腹腔鏡下胆嚢摘出術(4泊5日)",
      "subject" => { "reference" => "Patient/#{subject_id}" },
      "period" => { "start" => "2026-09-01" }
    }.deep_merge(overrides.deep_stringify_keys)
  end
end

RSpec.configure do |config|
  config.include CarePlanPayloadHelper, type: :request
end
