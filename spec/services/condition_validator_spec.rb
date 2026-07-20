require "rails_helper"

RSpec.describe ConditionValidator do
  let(:patient) do
    Fhir::Repository.create(
      "Patient",
      { "resourceType" => "Patient",
        "identifier" => [{ "system" => "urn:oid:1.2.392.100495.20.3.51", "value" => "P1" }] }
    )
  end

  def payload(overrides = {})
    {
      "resourceType" => "Condition",
      "clinicalStatus" => { "coding" => [{ "code" => "active" }] },
      "verificationStatus" => { "coding" => [{ "code" => "confirmed" }] },
      "code" => { "coding" => [{ "system" => "http://hl7.org/fhir/sid/icd-10", "code" => "J20.9" }] },
      "subject" => { "reference" => "Patient/#{patient.id}" }
    }.deep_merge(overrides.deep_stringify_keys)
  end

  it "is valid for a well-formed condition" do
    result = described_class.call(payload)

    expect(result).to be_valid
    expect(result.errors).to be_empty
  end

  it "is valid without clinicalStatus/verificationStatus (both optional)" do
    result = described_class.call(payload.except("clinicalStatus", "verificationStatus"))

    expect(result).to be_valid
  end

  it "rejects an invalid clinicalStatus" do
    result = described_class.call(payload("clinicalStatus" => { "coding" => [{ "code" => "bogus" }] }))

    expect(result).not_to be_valid
  end

  it "rejects an invalid verificationStatus" do
    result = described_class.call(payload("verificationStatus" => { "coding" => [{ "code" => "bogus" }] }))

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
