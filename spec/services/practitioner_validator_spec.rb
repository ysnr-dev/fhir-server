require "rails_helper"

RSpec.describe PractitionerValidator do
  def payload(overrides = {})
    { "resourceType" => "Practitioner" }.deep_merge(overrides.deep_stringify_keys)
  end

  it "is valid with no fields at all (JP Core: nothing is truly required)" do
    result = described_class.call(payload)

    expect(result).to be_valid
    expect(result.errors).to be_empty
  end

  %w[male female other unknown].each do |gender|
    it "accepts the valid gender '#{gender}'" do
      result = described_class.call(payload(gender: gender))

      expect(result).to be_valid
    end
  end

  it "rejects an invalid gender" do
    result = described_class.call(payload(gender: "invalid"))

    expect(result).not_to be_valid
    expect(result.errors.first[:code]).to eq("value")
  end

  it "accepts a partial birthDate (year only)" do
    result = described_class.call(payload(birthDate: "1980"))

    expect(result).to be_valid
  end

  it "rejects a malformed birthDate" do
    result = described_class.call(payload(birthDate: "01/01/1980"))

    expect(result).not_to be_valid
  end

  it "rejects an impossible calendar date" do
    result = described_class.call(payload(birthDate: "2020-02-30"))

    expect(result).not_to be_valid
  end
end
