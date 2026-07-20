require "rails_helper"

RSpec.describe ImmunizationValidator do
  let(:patient) do
    Fhir::Repository.create(
      "Patient",
      { "resourceType" => "Patient",
        "identifier" => [{ "system" => "urn:oid:1.2.392.100495.20.3.51", "value" => "P1" }] }
    )
  end

  def payload(overrides = {})
    {
      "resourceType" => "Immunization",
      "status" => "completed",
      "vaccineCode" => { "coding" => [{ "system" => "http://hl7.org/fhir/sid/ndc", "code" => "49281-0215-88" }] },
      "patient" => { "reference" => "Patient/#{patient.id}" },
      "occurrenceDateTime" => "2026-07-19T10:00:00+09:00"
    }.deep_merge(overrides.deep_stringify_keys)
  end

  it "is valid for a well-formed immunization" do
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

  it "requires vaccineCode" do
    result = described_class.call(payload.except("vaccineCode"))

    expect(result).not_to be_valid
  end

  it "requires patient" do
    result = described_class.call(payload.except("patient"))

    expect(result).not_to be_valid
  end

  it "rejects a patient reference to a non-existent patient" do
    result = described_class.call(payload("patient" => { "reference" => "Patient/does-not-exist" }))

    expect(result).not_to be_valid
  end

  it "rejects a malformed patient reference (not Patient/*)" do
    result = described_class.call(payload("patient" => { "reference" => "Device/123" }))

    expect(result).not_to be_valid
  end

  it "requires occurrenceDateTime" do
    result = described_class.call(payload.except("occurrenceDateTime"))

    expect(result).not_to be_valid
  end

  it "rejects an invalid occurrenceDateTime" do
    result = described_class.call(payload("occurrenceDateTime" => "not-a-date"))

    expect(result).not_to be_valid
  end
end
