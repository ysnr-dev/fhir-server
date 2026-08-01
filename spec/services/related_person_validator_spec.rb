require "rails_helper"

RSpec.describe RelatedPersonValidator do
  let(:patient) do
    Fhir::Repository.create(
      "Patient",
      { "resourceType" => "Patient",
        "identifier" => [{ "system" => "urn:oid:1.2.392.100495.20.3.51", "value" => "P1" }] }
    )
  end

  def payload(overrides = {})
    {
      "resourceType" => "RelatedPerson",
      "patient" => { "reference" => "Patient/#{patient.id}" },
      "relationship" => [
        { "coding" => [{ "system" => "http://terminology.hl7.org/CodeSystem/v3-RoleCode", "code" => "MTH" }] }
      ],
      "name" => [{ "use" => "official", "family" => "山田", "given" => ["花子"] }],
      "gender" => "female",
      "birthDate" => "1970-04-01"
    }.deep_merge(overrides.deep_stringify_keys)
  end

  it "is valid for a well-formed related person" do
    result = described_class.call(payload)

    expect(result).to be_valid
    expect(result.errors).to be_empty
  end

  # patient is the one mandatory element (1..1) in both R4 and JP_RelatedPerson.
  it "rejects a missing patient" do
    result = described_class.call(payload.except("patient"))

    expect(result).not_to be_valid
    expect(result.errors.first[:code]).to eq("required")
  end

  it "rejects a patient reference to a non-existent patient" do
    result = described_class.call(payload("patient" => { "reference" => "Patient/does-not-exist" }))

    expect(result).not_to be_valid
    expect(result.errors.first[:code]).to eq("invalid")
  end

  it "rejects a patient reference to a non-Patient resource" do
    result = described_class.call(payload("patient" => { "reference" => "Practitioner/pr1" }))

    expect(result).not_to be_valid
    expect(result.errors.first[:code]).to eq("value")
  end

  it "rejects an invalid gender" do
    result = described_class.call(payload("gender" => "bogus"))

    expect(result).not_to be_valid
  end

  it "rejects a malformed birthDate" do
    result = described_class.call(payload("birthDate" => "1970-13-45"))

    expect(result).not_to be_valid
  end

  it "rejects a non-boolean active" do
    result = described_class.call(payload("active" => "yes"))

    expect(result).not_to be_valid
  end

  it "is valid with only a patient" do
    result = described_class.call(
      { "resourceType" => "RelatedPerson", "patient" => { "reference" => "Patient/#{patient.id}" } }
    )

    expect(result).to be_valid
  end
end
