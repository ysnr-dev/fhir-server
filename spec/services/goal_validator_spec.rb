require "rails_helper"

RSpec.describe GoalValidator do
  def payload(**overrides)
    {
      "resourceType" => "Goal",
      "lifecycleStatus" => "active",
      "description" => { "text" => "疼痛がコントロールできる" },
      "subject" => { "reference" => "Patient/#{patient.id}" }
    }.merge(overrides.stringify_keys)
  end

  let(:patient) do
    Patient.create!(id: "p-goal", content: { "resourceType" => "Patient" }, last_updated: Time.current)
  end

  it "accepts a minimal valid goal" do
    expect(described_class.call(payload)).to be_valid
  end

  it "requires lifecycleStatus" do
    result = described_class.call(payload.except("lifecycleStatus"))

    expect(result).not_to be_valid
    expect(result.errors.first[:diagnostics]).to include("Goal.lifecycleStatus is required")
  end

  it "rejects a lifecycleStatus outside the value set" do
    result = described_class.call(payload(lifecycleStatus: "bogus"))

    expect(result).not_to be_valid
    expect(result.errors.first[:code]).to eq("value")
  end

  it "requires description" do
    expect(described_class.call(payload.except("description"))).not_to be_valid
    expect(described_class.call(payload(description: "疼痛"))).not_to be_valid
  end

  # achievementStatus の束縛は preferred。ePath のようにガイドが独自のコード体系を
  # 使うので、値は縛らず形だけを見る。
  it "accepts an achievementStatus from a non-HL7 code system" do
    result = described_class.call(
      payload(achievementStatus: {
                "coding" => [{ "system" => "http://e-path.jp/fhir/ePath/CodeSystem/EPathStateOfAchievementCS",
                               "code" => "2", "display" => "未達成（バリアンス）" }]
              })
    )

    expect(result).to be_valid
  end

  it "rejects an achievementStatus that is not a CodeableConcept" do
    expect(described_class.call(payload(achievementStatus: "achieved"))).not_to be_valid
  end

  it "requires subject" do
    expect(described_class.call(payload.except("subject"))).not_to be_valid
  end

  it "rejects a subject that references a non-existent patient" do
    result = described_class.call(payload(subject: { "reference" => "Patient/nope" }))

    expect(result).not_to be_valid
    expect(result.errors.first[:code]).to eq("invalid")
  end

  it "rejects malformed dates" do
    expect(described_class.call(payload(startDate: "not-a-date"))).not_to be_valid
    expect(described_class.call(payload(statusDate: "not-a-date"))).not_to be_valid
  end

  it "rejects a category that is not an array of CodeableConcepts" do
    expect(described_class.call(payload(category: { "text" => "x" }))).not_to be_valid
    expect(described_class.call(payload(category: [{ "text" => "x" }]))).to be_valid
  end
end
