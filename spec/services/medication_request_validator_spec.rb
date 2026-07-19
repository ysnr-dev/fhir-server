require "rails_helper"

RSpec.describe MedicationRequestValidator do
  let(:patient) do
    PatientRepository.create(
      { "resourceType" => "Patient",
        "identifier" => [{ "system" => "urn:oid:1.2.392.100495.20.3.51", "value" => "P1" }] }
    )
  end

  def payload(subject_reference, overrides = {})
    {
      "resourceType" => "MedicationRequest",
      "identifier" => [
        { "system" => "http://jpfhir.jp/fhir/core/mhlw/IdSystem/Medication-RPGroupNumber", "value" => "1" },
        { "system" => "http://jpfhir.jp/fhir/core/mhlw/IdSystem/MedicationAdministrationIndex", "value" => "1" }
      ],
      "status" => "active",
      "intent" => "order",
      "medicationCodeableConcept" => { "text" => "Drug" },
      "subject" => { "reference" => subject_reference },
      "authoredOn" => "2026-07-19T10:00:00+09:00"
    }.deep_merge(overrides.deep_stringify_keys)
  end

  it "is valid for a well-formed request referencing an existing patient" do
    result = described_class.call(payload("Patient/#{patient.id}"))

    expect(result).to be_valid
    expect(result.errors).to be_empty
  end

  it "requires at least one identifier" do
    result = described_class.call(payload("Patient/#{patient.id}").except("identifier"))

    expect(result).not_to be_valid
  end

  it "warns (but does not reject) when rpNumber/orderInRp slices are missing" do
    result = described_class.call(payload("Patient/#{patient.id}", "identifier" => [{ "value" => "1" }]))

    expect(result).to be_valid
    expect(result.warnings.size).to eq(2)
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

  it "requires medicationCodeableConcept" do
    result = described_class.call(payload("Patient/#{patient.id}").except("medicationCodeableConcept"))

    expect(result).not_to be_valid
  end

  it "rejects medicationReference (unsupported by JP Core)" do
    payload_hash = payload("Patient/#{patient.id}").except("medicationCodeableConcept")
    payload_hash["medicationReference"] = { "reference" => "Medication/123" }

    result = described_class.call(payload_hash)

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

  it "rejects a malformed subject reference (not Patient/*)" do
    result = described_class.call(payload("Practitioner/123"))

    expect(result).not_to be_valid
  end

  it "requires authoredOn" do
    result = described_class.call(payload("Patient/#{patient.id}").except("authoredOn"))

    expect(result).not_to be_valid
  end

  it "rejects a malformed authoredOn" do
    result = described_class.call(payload("Patient/#{patient.id}", "authoredOn" => "not-a-datetime"))

    expect(result).not_to be_valid
  end
end
