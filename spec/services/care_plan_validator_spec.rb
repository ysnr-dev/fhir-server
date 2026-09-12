require "rails_helper"

RSpec.describe CarePlanValidator do
  def payload(**overrides)
    {
      "resourceType" => "CarePlan",
      "status" => "active",
      "intent" => "plan",
      "subject" => { "reference" => "Patient/#{patient.id}" }
    }.merge(overrides.stringify_keys)
  end

  let(:patient) do
    Patient.create!(id: "p-care-plan", content: { "resourceType" => "Patient" }, last_updated: Time.current)
  end

  it "accepts a minimal valid care plan" do
    expect(described_class.call(payload)).to be_valid
  end

  it "requires status" do
    result = described_class.call(payload.except("status"))

    expect(result).not_to be_valid
    expect(result.errors.first[:diagnostics]).to include("CarePlan.status is required")
  end

  it "rejects a status outside the value set" do
    result = described_class.call(payload(status: "bogus"))

    expect(result).not_to be_valid
    expect(result.errors.first[:code]).to eq("value")
  end

  it "requires intent and rejects one outside the value set" do
    expect(described_class.call(payload.except("intent"))).not_to be_valid
    expect(described_class.call(payload(intent: "order"))).to be_valid
    expect(described_class.call(payload(intent: "bogus"))).not_to be_valid
  end

  it "requires subject" do
    expect(described_class.call(payload.except("subject"))).not_to be_valid
  end

  it "rejects a subject that references a non-existent patient" do
    result = described_class.call(payload(subject: { "reference" => "Patient/nope" }))

    expect(result).not_to be_valid
    expect(result.errors.first[:code]).to eq("invalid")
  end

  # CarePlan.subject in R4 also allows Group.
  it "accepts a non-Patient subject without a lookup" do
    expect(described_class.call(payload(subject: { "reference" => "Group/cohort-1" }))).to be_valid
  end

  it "rejects a malformed period" do
    result = described_class.call(payload(period: { "start" => "not-a-date" }))

    expect(result).not_to be_valid
    expect(result.errors.first[:expression]).to eq(["CarePlan.period.start"])
  end

  it "rejects a category that is not an array of CodeableConcepts" do
    expect(described_class.call(payload(category: { "text" => "x" }))).not_to be_valid
    expect(described_class.call(payload(category: ["x"]))).not_to be_valid
    expect(described_class.call(payload(category: [{ "text" => "x" }]))).to be_valid
  end

  # part-of / goal は jsonb 包含で引くので、配列でないと静かに引けなくなる。
  it "rejects partOf and goal that are not arrays" do
    result = described_class.call(payload(partOf: { "reference" => "CarePlan/x" }))

    expect(result).not_to be_valid
    expect(result.errors.first[:diagnostics]).to include("searched by `part-of`")
    expect(described_class.call(payload(goal: { "reference" => "Goal/x" }))).not_to be_valid
  end
end
