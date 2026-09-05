require "rails_helper"

RSpec.describe FlagValidator do
  def payload(**overrides)
    {
      "resourceType" => "Flag",
      "status" => "active",
      "code" => { "coding" => [{ "system" => "http://fhir-client.local/CodeSystem/patient-caution",
                                 "code" => "fall" }] },
      "subject" => { "reference" => "Patient/#{patient.id}" }
    }.merge(overrides.stringify_keys)
  end

  let(:patient) do
    Patient.create!(id: "p-flag", content: { "resourceType" => "Patient" }, last_updated: Time.current)
  end

  it "accepts a minimal valid flag" do
    expect(described_class.call(payload)).to be_valid
  end

  it "requires status" do
    result = described_class.call(payload.except("status"))

    expect(result).not_to be_valid
    expect(result.errors.first[:diagnostics]).to include("Flag.status is required")
  end

  it "rejects a status outside the value set" do
    result = described_class.call(payload(status: "bogus"))

    expect(result).not_to be_valid
    expect(result.errors.first[:code]).to eq("value")
  end

  it "requires code" do
    expect(described_class.call(payload.except("code"))).not_to be_valid
  end

  it "requires subject" do
    expect(described_class.call(payload.except("subject"))).not_to be_valid
  end

  it "rejects a subject that references a non-existent patient" do
    result = described_class.call(payload(subject: { "reference" => "Patient/nope" }))

    expect(result).not_to be_valid
    expect(result.errors.first[:code]).to eq("invalid")
  end

  # Flag.subject in R4 also allows Location / Group / Organization etc.
  it "accepts a non-Patient subject without a lookup" do
    expect(described_class.call(payload(subject: { "reference" => "Location/room-1" }))).to be_valid
  end

  it "rejects a malformed period" do
    result = described_class.call(payload(period: { "start" => "not-a-date" }))

    expect(result).not_to be_valid
    expect(result.errors.first[:expression]).to eq(["Flag.period.start"])
  end
end
