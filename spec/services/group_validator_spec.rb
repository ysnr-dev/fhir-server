require "rails_helper"

RSpec.describe GroupValidator do
  let(:patient) do
    Fhir::Repository.create(
      "Patient",
      { "resourceType" => "Patient",
        "identifier" => [{ "system" => "urn:oid:1.2.392.100495.20.3.51", "value" => "P1" }] }
    )
  end

  def payload(overrides = {})
    {
      "resourceType" => "Group",
      "type" => "person",
      "actual" => true,
      "name" => "2026年度 特定健診対象者"
    }.deep_merge(overrides.deep_stringify_keys)
  end

  it "is valid for a well-formed group" do
    result = described_class.call(payload)

    expect(result).to be_valid
    expect(result.errors).to be_empty
  end

  it "rejects a missing type" do
    result = described_class.call(payload.except("type"))

    expect(result).not_to be_valid
    expect(result.errors.first[:code]).to eq("required")
  end

  it "rejects an invalid type" do
    result = described_class.call(payload("type" => "bogus"))

    expect(result).not_to be_valid
    expect(result.errors.first[:code]).to eq("value")
  end

  # actual is 1..1 and false is a meaningful value, so requiredness must not be
  # confused with truthiness.
  it "rejects a missing actual" do
    result = described_class.call(payload.except("actual"))

    expect(result).not_to be_valid
    expect(result.errors.first[:code]).to eq("required")
  end

  it "accepts actual: false" do
    result = described_class.call(payload("actual" => false))

    expect(result).to be_valid
  end

  it "accepts members referencing existing patients" do
    result = described_class.call(
      payload("member" => [{ "entity" => { "reference" => "Patient/#{patient.id}" } }])
    )

    expect(result).to be_valid
  end

  # A dangling Patient member would silently shrink Group/$export rather than
  # fail it, so it is rejected at write time.
  it "rejects a member referencing a non-existent patient" do
    result = described_class.call(
      payload("member" => [{ "entity" => { "reference" => "Patient/does-not-exist" } }])
    )

    expect(result).not_to be_valid
    expect(result.errors.first[:code]).to eq("invalid")
  end

  it "accepts non-Patient members without resolving them" do
    result = described_class.call(
      payload("member" => [{ "entity" => { "reference" => "Practitioner/never-created" } }])
    )

    expect(result).to be_valid
  end

  it "rejects a member with no entity reference" do
    result = described_class.call(payload("member" => [{ "period" => { "start" => "2026-01-01" } }]))

    expect(result).not_to be_valid
    expect(result.errors.first[:code]).to eq("required")
  end

  # grp-1: members are only meaningful on an actual (roster-based) group.
  it "rejects members on a descriptive group" do
    result = described_class.call(
      payload("actual" => false, "member" => [{ "entity" => { "reference" => "Patient/#{patient.id}" } }])
    )

    expect(result).not_to be_valid
    expect(result.errors.map { |e| e[:code] }).to include("invariant")
  end

  it "rejects a non-array member" do
    result = described_class.call(payload("member" => { "entity" => { "reference" => "Patient/#{patient.id}" } }))

    expect(result).not_to be_valid
    expect(result.errors.map { |e| e[:code] }).to include("structure")
  end
end
