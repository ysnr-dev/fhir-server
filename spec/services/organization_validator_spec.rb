require "rails_helper"

RSpec.describe OrganizationValidator do
  def payload(overrides = {})
    { "resourceType" => "Organization" }.deep_merge(overrides.deep_stringify_keys)
  end

  it "is valid when only identifier is present" do
    result = described_class.call(payload("identifier" => [{ "system" => "http://example.org", "value" => "1" }]))

    expect(result).to be_valid
  end

  it "is valid when only name is present" do
    result = described_class.call(payload("name" => "サンプル病院"))

    expect(result).to be_valid
  end

  it "is invalid when both identifier and name are absent (org-1)" do
    result = described_class.call(payload)

    expect(result).not_to be_valid
    expect(result.errors.first[:code]).to eq("invariant")
  end

  it "is invalid when identifier is an empty array and name is absent" do
    result = described_class.call(payload("identifier" => []))

    expect(result).not_to be_valid
  end
end
