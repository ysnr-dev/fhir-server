require "rails_helper"

RSpec.describe SpecimenValidator do
  let(:patient) do
    Fhir::Repository.create(
      "Patient",
      { "resourceType" => "Patient",
        "identifier" => [{ "system" => "urn:oid:1.2.392.100495.20.3.51", "value" => "P1" }] }
    )
  end

  def payload(overrides = {})
    {
      "resourceType" => "Specimen",
      "status" => "available",
      "type" => { "coding" => [{ "code" => "BLD" }] },
      "subject" => { "reference" => "Patient/#{patient.id}" }
    }.deep_merge(overrides.deep_stringify_keys)
  end

  it "is valid for a well-formed specimen" do
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

  it "is valid without a subject (subject is optional)" do
    result = described_class.call(payload.except("subject"))

    expect(result).to be_valid
  end

  it "rejects a subject reference to a non-existent patient" do
    result = described_class.call(payload("subject" => { "reference" => "Patient/does-not-exist" }))

    expect(result).not_to be_valid
  end

  it "accepts a non-Patient subject reference (skipped)" do
    result = described_class.call(payload("subject" => { "reference" => "Device/123" }))

    expect(result).to be_valid
  end
end
