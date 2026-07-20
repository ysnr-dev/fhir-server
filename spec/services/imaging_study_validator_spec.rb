require "rails_helper"

RSpec.describe ImagingStudyValidator do
  let(:patient) do
    Fhir::Repository.create(
      "Patient",
      { "resourceType" => "Patient",
        "identifier" => [{ "system" => "urn:oid:1.2.392.100495.20.3.51", "value" => "P1" }] }
    )
  end

  def payload(subject_reference, overrides = {})
    {
      "resourceType" => "ImagingStudy",
      "status" => "available",
      "subject" => { "reference" => subject_reference }
    }.deep_merge(overrides.deep_stringify_keys)
  end

  it "is valid for a well-formed study referencing an existing patient" do
    result = described_class.call(payload("Patient/#{patient.id}"))

    expect(result).to be_valid
    expect(result.errors).to be_empty
  end

  it "requires status" do
    result = described_class.call(payload("Patient/#{patient.id}").except("status"))

    expect(result).not_to be_valid
  end

  it "rejects an invalid status" do
    result = described_class.call(payload("Patient/#{patient.id}", "status" => "bogus"))

    expect(result).not_to be_valid
  end

  it "requires subject" do
    result = described_class.call(payload("Patient/#{patient.id}").except("subject"))

    expect(result).not_to be_valid
  end

  it "rejects a subject reference to a non-existent patient" do
    result = described_class.call(payload("Patient/does-not-exist"))

    expect(result).not_to be_valid
  end

  it "rejects a malformed subject reference (not Patient/*)" do
    result = described_class.call(payload("Device/123"))

    expect(result).not_to be_valid
  end
end
