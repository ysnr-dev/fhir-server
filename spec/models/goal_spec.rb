require "rails_helper"

RSpec.describe Goal do
  def build_goal(content)
    described_class.new(
      id: SecureRandom.uuid,
      version_id: 1,
      content: content,
      last_updated: Time.current
    )
  end

  describe "#sync_search_fields!" do
    it "extracts the lifecycle and achievement status, subject, and start date" do
      goal = build_goal(
        "lifecycleStatus" => "completed",
        "achievementStatus" => {
          "coding" => [{ "system" => "http://e-path.jp/fhir/ePath/CodeSystem/EPathStateOfAchievementCS",
                         "code" => "2", "display" => "未達成（バリアンス）" }]
        },
        "description" => { "text" => "疼痛がコントロールできる" },
        "subject" => { "reference" => "Patient/abc123" },
        "startDate" => "2026-09-01"
      )

      goal.sync_search_fields!

      expect(goal.lifecycle_status).to eq("completed")
      expect(goal.achievement_status).to eq("2")
      expect(goal.subject_reference).to eq("Patient/abc123")
      expect(goal.start_date).to eq(Date.new(2026, 9, 1))
    end

    # start[x] は choice。契機をコードで書いた目標は start_date を持たない。
    it "leaves start_date null when the start is a CodeableConcept" do
      goal = build_goal(
        "lifecycleStatus" => "active",
        "startCodeableConcept" => { "text" => "手術当日" }
      )

      goal.sync_search_fields!

      expect(goal.start_date).to be_nil
    end

    it "is nil-safe when fields are absent" do
      goal = build_goal({})

      goal.sync_search_fields!

      expect(goal.lifecycle_status).to be_nil
      expect(goal.achievement_status).to be_nil
      expect(goal.subject_reference).to be_nil
    end
  end
end
