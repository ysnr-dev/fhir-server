require "rails_helper"

RSpec.describe CareTeamValidator do
  def payload(**overrides)
    {
      "resourceType" => "CareTeam",
      "status" => "active",
      "name" => "栄養サポートチーム",
      "participant" => [{ "member" => { "reference" => "Practitioner/dr-1" } }]
    }.merge(overrides.stringify_keys)
  end

  let(:patient) do
    Patient.create!(id: "p-care-team", content: { "resourceType" => "Patient" }, last_updated: Time.current)
  end

  it "accepts an organizational team without a subject" do
    expect(described_class.call(payload)).to be_valid
  end

  it "accepts a patient care team whose subject exists" do
    expect(described_class.call(payload(subject: { "reference" => "Patient/#{patient.id}" }))).to be_valid
  end

  it "requires status" do
    result = described_class.call(payload.except("status"))

    expect(result).not_to be_valid
    expect(result.errors.first[:diagnostics]).to include("CareTeam.status is required")
  end

  it "rejects a status outside the value set" do
    result = described_class.call(payload(status: "bogus"))

    expect(result).not_to be_valid
    expect(result.errors.first[:code]).to eq("value")
  end

  it "rejects a subject that references a non-existent patient" do
    result = described_class.call(payload(subject: { "reference" => "Patient/nope" }))

    expect(result).not_to be_valid
    expect(result.errors.first[:code]).to eq("invalid")
  end

  it "rejects a participant that is not an array, and a member without a typed reference" do
    expect(described_class.call(payload(participant: { "member" => {} }))).not_to be_valid

    result = described_class.call(payload(participant: [{ "member" => { "reference" => "dr-1" } }]))
    expect(result).not_to be_valid
    expect(result.errors.first[:expression]).to eq(["CareTeam.participant[0].member.reference"])
  end

  it "rejects a malformed period" do
    result = described_class.call(payload(period: { "start" => "not-a-date" }))

    expect(result).not_to be_valid
    expect(result.errors.first[:expression]).to eq(["CareTeam.period.start"])
  end
end
