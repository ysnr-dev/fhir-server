require "rails_helper"

RSpec.describe PatientValidator do
  def payload(overrides = {})
    {
      "resourceType" => "Patient",
      "identifier" => [
        { "system" => "urn:oid:1.2.392.100495.20.3.51", "value" => "12345" }
      ],
      "gender" => "male",
      "birthDate" => "1990-01-01"
    }.deep_merge(overrides.deep_stringify_keys)
  end

  it "is valid for a well-formed JP-Core patient" do
    result = described_class.call(payload)

    expect(result).to be_valid
    expect(result.errors).to be_empty
  end

  it "requires at least one identifier" do
    result = described_class.call(payload.except("identifier"))

    expect(result).not_to be_valid
    expect(result.errors.first[:code]).to eq("required")
  end

  it "requires identifier.value to be present" do
    result = described_class.call(payload("identifier" => [{ "system" => "urn:oid:1.2.392.100495.20.3.51" }]))

    expect(result).not_to be_valid
  end

  it "rejects an invalid gender" do
    result = described_class.call(payload(gender: "invalid"))

    expect(result).not_to be_valid
    expect(result.errors.first[:code]).to eq("value")
  end

  %w[male female other unknown].each do |gender|
    it "accepts the valid gender '#{gender}'" do
      result = described_class.call(payload(gender: gender))

      expect(result).to be_valid
    end
  end

  it "accepts partial birthDate (year only)" do
    result = described_class.call(payload(birthDate: "1990"))

    expect(result).to be_valid
  end

  it "accepts partial birthDate (year-month)" do
    result = described_class.call(payload(birthDate: "1990-05"))

    expect(result).to be_valid
  end

  it "rejects a malformed birthDate" do
    result = described_class.call(payload(birthDate: "01/01/1990"))

    expect(result).not_to be_valid
  end

  it "rejects an impossible calendar date" do
    result = described_class.call(payload(birthDate: "2020-02-30"))

    expect(result).not_to be_valid
  end

  it "rejects deceasedBoolean and deceasedDateTime present together" do
    result = described_class.call(payload("deceasedBoolean" => true, "deceasedDateTime" => "2020-01-01T00:00:00Z"))

    expect(result).not_to be_valid
    expect(result.errors.map { |e| e[:code] }).to include("invariant")
  end

  it "rejects a non-boolean deceasedBoolean" do
    result = described_class.call(payload("deceasedBoolean" => "yes"))

    expect(result).not_to be_valid
  end

  it "rejects an invalid deceasedDateTime" do
    result = described_class.call(payload("deceasedDateTime" => "not-a-datetime"))

    expect(result).not_to be_valid
  end

  it "requires communication.language when communication is present" do
    result = described_class.call(payload("communication" => [{}]))

    expect(result).not_to be_valid
  end

  it "accepts communication with a language" do
    result = described_class.call(payload("communication" => [{ "language" => { "coding" => [{ "code" => "ja" }] } }]))

    expect(result).to be_valid
  end

  it "warns (but does not reject) an MR identifier with a non-standard system" do
    result = described_class.call(
      payload("identifier" => [
                {
                  "type" => { "coding" => [{ "code" => "MR" }] },
                  "system" => "http://example.org/mrn",
                  "value" => "999"
                }
              ])
    )

    expect(result).to be_valid
    expect(result.warnings).not_to be_empty
  end
end
