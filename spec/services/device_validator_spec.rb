require "rails_helper"

RSpec.describe DeviceValidator do
  let(:patient) do
    Fhir::Repository.create(
      "Patient",
      { "resourceType" => "Patient",
        "identifier" => [{ "system" => "urn:oid:1.2.392.100495.20.3.51", "value" => "P1" }] }
    )
  end

  def payload(overrides = {})
    {
      "resourceType" => "Device",
      "status" => "active",
      "type" => { "coding" => [{ "code" => "706172005" }] },
      "manufacturer" => "サンプル医療機器"
    }.deep_merge(overrides.deep_stringify_keys)
  end

  it "is valid for a well-formed device" do
    result = described_class.call(payload)

    expect(result).to be_valid
    expect(result.errors).to be_empty
  end

  # Device has no 1.. elements in base R4 or JP_Device, so an empty resource
  # is conformant -- requiredness is genuinely absent, not merely unchecked.
  it "is valid with no elements at all" do
    result = described_class.call({ "resourceType" => "Device" })

    expect(result).to be_valid
  end

  it "rejects an invalid status" do
    result = described_class.call(payload("status" => "bogus"))

    expect(result).not_to be_valid
    expect(result.errors.first[:code]).to eq("value")
  end

  it "accepts a patient reference to an existing patient" do
    result = described_class.call(payload("patient" => { "reference" => "Patient/#{patient.id}" }))

    expect(result).to be_valid
  end

  it "rejects a patient reference to a non-existent patient" do
    result = described_class.call(payload("patient" => { "reference" => "Patient/does-not-exist" }))

    expect(result).not_to be_valid
    expect(result.errors.first[:expression]).to eq(["Device.patient.reference"])
  end

  # Device.patient targets Patient only, so another target type is a value error
  # rather than an allowed alternative.
  it "rejects a patient reference to a non-Patient resource" do
    result = described_class.call(payload("patient" => { "reference" => "Organization/o1" }))

    expect(result).not_to be_valid
    expect(result.errors.first[:code]).to eq("value")
  end

  it "rejects a malformed manufactureDate" do
    result = described_class.call(payload("manufactureDate" => "not-a-date"))

    expect(result).not_to be_valid
  end

  it "accepts a partial expirationDate" do
    result = described_class.call(payload("expirationDate" => "2030-06"))

    expect(result).to be_valid
  end
end
