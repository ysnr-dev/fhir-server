require "rails_helper"

RSpec.describe PractitionerRoleValidator do
  def payload(overrides = {})
    {
      "resourceType" => "PractitionerRole",
      "active" => true,
      "practitioner" => { "reference" => "Practitioner/p1" }
    }.deep_merge(overrides.deep_stringify_keys)
  end

  it "is valid for a well-formed practitioner role" do
    expect(described_class.call(payload)).to be_valid
  end

  it "is valid with no fields (JP Core has no required elements)" do
    expect(described_class.call({ "resourceType" => "PractitionerRole" })).to be_valid
  end

  it "rejects a non-boolean active" do
    expect(described_class.call(payload("active" => "yes"))).not_to be_valid
  end
end
