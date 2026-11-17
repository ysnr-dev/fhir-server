require "rails_helper"

RSpec.describe FamilyMemberHistoryValidator do
  let(:patient) do
    Patient.create!(id: "p-family-history", content: { "resourceType" => "Patient" }, last_updated: Time.current)
  end

  def payload(**overrides)
    {
      "resourceType" => "FamilyMemberHistory",
      "status" => "completed",
      "patient" => { "reference" => "Patient/#{patient.id}" },
      "relationship" => { "coding" => [{ "system" => "http://terminology.hl7.org/CodeSystem/v3-RoleCode", "code" => "MTH" }] },
      "condition" => [{ "code" => { "text" => "糖尿病" } }]
    }.merge(overrides.stringify_keys)
  end

  it "accepts a valid payload, with or without conditions" do
    expect(described_class.call(payload)).to be_valid
    expect(described_class.call(payload.except("condition"))).to be_valid
  end

  it "requires status and rejects one outside the value set" do
    result = described_class.call(payload.except("status"))
    expect(result).not_to be_valid
    expect(result.errors.first[:diagnostics]).to include("FamilyMemberHistory.status is required")

    result = described_class.call(payload(status: "bogus"))
    expect(result).not_to be_valid
    expect(result.errors.first[:code]).to eq("value")
  end

  it "requires relationship" do
    result = described_class.call(payload.except("relationship"))

    expect(result).not_to be_valid
    expect(result.errors.first[:expression]).to eq(["FamilyMemberHistory.relationship"])
  end

  it "requires a patient that exists and is a Patient reference" do
    expect(described_class.call(payload.except("patient"))).not_to be_valid

    result = described_class.call(payload(patient: { "reference" => "Patient/nope" }))
    expect(result).not_to be_valid
    expect(result.errors.first[:code]).to eq("invalid")

    result = described_class.call(payload(patient: { "reference" => "Group/g1" }))
    expect(result).not_to be_valid
    expect(result.errors.first[:code]).to eq("value")
  end

  it "rejects a malformed date" do
    result = described_class.call(payload(date: "not-a-date"))

    expect(result).not_to be_valid
    expect(result.errors.first[:expression]).to eq(["FamilyMemberHistory.date"])
  end

  it "rejects a condition that is not an array, and a condition without a code" do
    expect(described_class.call(payload(condition: { "code" => { "text" => "x" } }))).not_to be_valid

    result = described_class.call(payload(condition: [{ "code" => { "text" => "糖尿病" } }, { "note" => [] }]))
    expect(result).not_to be_valid
    expect(result.errors.first[:expression]).to eq(["FamilyMemberHistory.condition[1].code"])
  end
end
