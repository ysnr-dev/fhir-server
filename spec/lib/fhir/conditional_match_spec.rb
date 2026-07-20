require "rails_helper"

RSpec.describe Fhir::ConditionalMatch do
  def create_patient(identifier_value)
    Fhir::Repository.create(
      "Patient",
      { "resourceType" => "Patient",
        "identifier" => [{ "system" => "urn:oid:1.2.392.100495.20.3.51", "value" => identifier_value }] }
    )
  end

  it "returns :invalid for empty criteria" do
    result = described_class.call("Patient", "")

    expect(result.outcome).to eq(:invalid)
    expect(result.diagnostics).to include("at least one search parameter")
  end

  it "returns :invalid for an unknown search parameter" do
    result = described_class.call("Patient", "bogus-param=1")

    expect(result.outcome).to eq(:invalid)
    expect(result.diagnostics).to include("bogus-param")
  end

  it "returns :invalid for an unsupported modifier" do
    result = described_class.call("Patient", "identifier:bogus=X")

    expect(result.outcome).to eq(:invalid)
  end

  it "returns :none when nothing matches" do
    result = described_class.call("Patient", "identifier=no-such-value")

    expect(result.outcome).to eq(:none)
    expect(result.record).to be_nil
  end

  it "returns :one with the record when exactly one matches" do
    patient = create_patient("cm-one")

    result = described_class.call("Patient", "identifier=cm-one")

    expect(result.outcome).to eq(:one)
    expect(result.record.id).to eq(patient.id)
  end

  it "matches on system|value identifier criteria" do
    patient = create_patient("cm-sys")

    result = described_class.call("Patient", "identifier=urn:oid:1.2.392.100495.20.3.51|cm-sys")

    expect(result.outcome).to eq(:one)
    expect(result.record.id).to eq(patient.id)
  end

  it "returns :multiple when more than one matches" do
    create_patient("cm-dup")
    create_patient("cm-dup")

    result = described_class.call("Patient", "identifier=cm-dup")

    expect(result.outcome).to eq(:multiple)
    expect(result.diagnostics).to include("Multiple Patient")
  end

  it "does not match deleted resources" do
    patient = create_patient("cm-deleted")
    Fhir::Repository.delete("Patient", patient)

    result = described_class.call("Patient", "identifier=cm-deleted")

    expect(result.outcome).to eq(:none)
  end
end
