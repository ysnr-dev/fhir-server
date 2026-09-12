module GoalPayloadHelper
  # achievementStatus の束縛は preferred なので、ePath のようにガイド独自のコード体系を
  # 使ってよい。ここでも施設ローカルの体系で書き、HL7 のコードに縛られないことを示す。
  ACHIEVEMENT_SYSTEM = "http://e-path.jp/fhir/ePath/CodeSystem/EPathStateOfAchievementCS".freeze

  def valid_goal_payload(subject_id:, **overrides)
    {
      "resourceType" => "Goal",
      "identifier" => [{ "system" => "http://example.org/goal", "value" => "GL1" }],
      "lifecycleStatus" => "active",
      "achievementStatus" => {
        "coding" => [{ "system" => ACHIEVEMENT_SYSTEM, "code" => "1", "display" => "達成" }]
      },
      "description" => { "text" => "疼痛がコントロールできる" },
      "subject" => { "reference" => "Patient/#{subject_id}" },
      "startDate" => "2026-09-01"
    }.deep_merge(overrides.deep_stringify_keys)
  end
end

RSpec.configure do |config|
  config.include GoalPayloadHelper, type: :request
end
