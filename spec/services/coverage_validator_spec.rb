require "rails_helper"

RSpec.describe CoverageValidator do
  let(:patient) do
    Fhir::Repository.create(
      "Patient",
      { "resourceType" => "Patient",
        "identifier" => [{ "system" => "urn:oid:1.2.392.100495.20.3.51", "value" => "P1" }] }
    )
  end

  let(:organization) do
    Fhir::Repository.create("Organization", { "resourceType" => "Organization", "name" => "健保組合" })
  end

  def payload(overrides = {})
    {
      "resourceType" => "Coverage",
      "status" => "active",
      "beneficiary" => { "reference" => "Patient/#{patient.id}" },
      "payor" => [{ "reference" => "Organization/#{organization.id}" }]
    }.deep_merge(overrides.deep_stringify_keys)
  end

  it "is valid for a well-formed coverage" do
    result = described_class.call(payload)

    expect(result).to be_valid
    expect(result.errors).to be_empty
  end

  it "requires status" do
    result = described_class.call(payload.except("status"))

    expect(result).not_to be_valid
  end

  it "rejects an invalid status" do
    result = described_class.call(payload("status" => "bogus"))

    expect(result).not_to be_valid
  end

  it "requires beneficiary" do
    result = described_class.call(payload.except("beneficiary"))

    expect(result).not_to be_valid
  end

  it "rejects a beneficiary reference to a non-existent patient" do
    result = described_class.call(payload("beneficiary" => { "reference" => "Patient/does-not-exist" }))

    expect(result).not_to be_valid
  end

  it "rejects a malformed beneficiary reference (not Patient/*)" do
    result = described_class.call(payload("beneficiary" => { "reference" => "Device/123" }))

    expect(result).not_to be_valid
  end

  it "requires at least one payor" do
    result = described_class.call(payload.except("payor"))

    expect(result).not_to be_valid
  end

  it "rejects an empty payor array" do
    result = described_class.call(payload("payor" => []))

    expect(result).not_to be_valid
  end
end
