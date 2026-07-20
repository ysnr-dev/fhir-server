require "rails_helper"

RSpec.describe LocationValidator do
  def payload(overrides = {})
    {
      "resourceType" => "Location",
      "status" => "active",
      "name" => "第1診察室",
      "mode" => "instance"
    }.deep_merge(overrides.deep_stringify_keys)
  end

  it "is valid for a well-formed location" do
    expect(described_class.call(payload)).to be_valid
  end

  it "is valid with no fields (JP Core has no required elements)" do
    expect(described_class.call({ "resourceType" => "Location" })).to be_valid
  end

  it "rejects an invalid status" do
    expect(described_class.call(payload("status" => "bogus"))).not_to be_valid
  end

  it "rejects an invalid mode" do
    expect(described_class.call(payload("mode" => "bogus"))).not_to be_valid
  end
end
