require "rails_helper"

RSpec.describe AllergyIntoleranceValidator do
  let(:patient) do
    Fhir::Repository.create(
      "Patient",
      { "resourceType" => "Patient",
        "identifier" => [{ "system" => "urn:oid:1.2.392.100495.20.3.51", "value" => "P1" }] }
    )
  end

  def payload(overrides = {})
    {
      "resourceType" => "AllergyIntolerance",
      "clinicalStatus" => { "coding" => [{ "code" => "active" }] },
      "verificationStatus" => { "coding" => [{ "code" => "confirmed" }] },
      "type" => "allergy",
      "category" => ["medication"],
      "criticality" => "high",
      "code" => { "coding" => [{ "system" => "http://www.nlm.nih.gov/research/umls/rxnorm", "code" => "7980" }] },
      "patient" => { "reference" => "Patient/#{patient.id}" }
    }.deep_merge(overrides.deep_stringify_keys)
  end

  it "is valid for a well-formed allergy intolerance" do
    result = described_class.call(payload)

    expect(result).to be_valid
    expect(result.errors).to be_empty
  end

  it "is valid with only patient set (everything else optional)" do
    result = described_class.call(payload.slice("resourceType", "patient"))

    expect(result).to be_valid
  end

  it "rejects an invalid type" do
    result = described_class.call(payload("type" => "bogus"))

    expect(result).not_to be_valid
  end

  it "rejects an invalid category" do
    result = described_class.call(payload("category" => ["bogus"]))

    expect(result).not_to be_valid
  end

  it "rejects an invalid criticality" do
    result = described_class.call(payload("criticality" => "bogus"))

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
end
