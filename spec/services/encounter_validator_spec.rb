require "rails_helper"

RSpec.describe EncounterValidator do
  def payload(overrides = {})
    {
      "resourceType" => "Encounter",
      "status" => "finished",
      "class" => { "system" => "http://terminology.hl7.org/CodeSystem/v3-ActCode", "code" => "AMB" },
      "subject" => { "reference" => "Patient/abc123" }
    }.deep_merge(overrides.deep_stringify_keys)
  end

  it "is valid for a well-formed encounter" do
    expect(described_class.call(payload)).to be_valid
  end

  it "requires status" do
    expect(described_class.call(payload.except("status"))).not_to be_valid
  end

  it "rejects an invalid status" do
    expect(described_class.call(payload("status" => "bogus"))).not_to be_valid
  end

  it "requires class" do
    expect(described_class.call(payload.except("class"))).not_to be_valid
  end

  it "accepts any class code (extensible binding)" do
    expect(described_class.call(payload("class" => { "code" => "IMP" }))).to be_valid
  end

  it "does not require subject" do
    expect(described_class.call(payload.except("subject"))).to be_valid
  end
end
