require "rails_helper"

RSpec.describe MedicationValidator do
  def payload(overrides = {})
    {
      "resourceType" => "Medication",
      "status" => "active",
      "code" => { "text" => "Drug" }
    }.deep_merge(overrides.deep_stringify_keys)
  end

  it "is valid for a well-formed medication" do
    result = described_class.call(payload)

    expect(result).to be_valid
    expect(result.errors).to be_empty
  end

  it "is valid without a status (status is optional)" do
    result = described_class.call(payload.except("status"))

    expect(result).to be_valid
  end

  it "rejects an invalid status" do
    result = described_class.call(payload("status" => "bogus"))

    expect(result).not_to be_valid
  end

  it "requires code" do
    result = described_class.call(payload.except("code"))

    expect(result).not_to be_valid
  end
end
