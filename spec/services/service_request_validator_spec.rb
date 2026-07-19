require "rails_helper"

RSpec.describe ServiceRequestValidator do
  let(:patient) do
    PatientRepository.create(
      { "resourceType" => "Patient",
        "identifier" => [{ "system" => "urn:oid:1.2.392.100495.20.3.51", "value" => "P1" }] }
    )
  end

  def payload(subject_reference, overrides = {})
    {
      "resourceType" => "ServiceRequest",
      "status" => "active",
      "intent" => "order",
      "subject" => { "reference" => subject_reference }
    }.deep_merge(overrides.deep_stringify_keys)
  end

  it "is valid for a well-formed request referencing an existing patient" do
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

  it "requires intent" do
    result = described_class.call(payload("Patient/#{patient.id}").except("intent"))

    expect(result).not_to be_valid
  end

  it "rejects an invalid intent" do
    result = described_class.call(payload("Patient/#{patient.id}", "intent" => "bogus"))

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

  it "rejects a subject reference to a deleted patient" do
    PatientRepository.delete(patient)

    result = described_class.call(payload("Patient/#{patient.id}"))

    expect(result).not_to be_valid
  end

  it "accepts a non-Patient subject reference without an existence check" do
    result = described_class.call(payload("Location/some-location"))

    expect(result).to be_valid
  end

  it "does not require identifier" do
    result = described_class.call(payload("Patient/#{patient.id}"))

    expect(result.errors.map { |e| e[:expression] }.flatten).not_to include("ServiceRequest.identifier")
  end
end
