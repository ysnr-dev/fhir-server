require "rails_helper"

RSpec.describe ProcedureValidator do
  let(:patient) do
    Fhir::Repository.create(
      "Patient",
      { "resourceType" => "Patient",
        "identifier" => [{ "system" => "urn:oid:1.2.392.100495.20.3.51", "value" => "P1" }] }
    )
  end

  def payload(overrides = {})
    {
      "resourceType" => "Procedure",
      "status" => "completed",
      "code" => { "coding" => [{ "system" => "http://snomed.info/sct", "code" => "80146002" }] },
      "subject" => { "reference" => "Patient/#{patient.id}" }
    }.deep_merge(overrides.deep_stringify_keys)
  end

  it "is valid for a well-formed procedure" do
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

  it "requires subject" do
    result = described_class.call(payload.except("subject"))

    expect(result).not_to be_valid
  end

  it "rejects a subject reference to a non-existent patient" do
    result = described_class.call(payload("subject" => { "reference" => "Patient/does-not-exist" }))

    expect(result).not_to be_valid
  end

  it "rejects a malformed subject reference (not Patient/*)" do
    result = described_class.call(payload("subject" => { "reference" => "Device/123" }))

    expect(result).not_to be_valid
  end
end
