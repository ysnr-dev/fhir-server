require "rails_helper"

RSpec.describe CompositionValidator do
  def base_payload
    {
      "resourceType" => "Composition",
      "status" => "final",
      "type" => { "coding" => [{ "system" => "http://loinc.org", "code" => "18842-5" }] },
      "date" => "2026-07-22T10:00:00+09:00",
      "author" => [{ "reference" => "Practitioner/unknown" }],
      "title" => "退院時サマリ"
    }
  end

  it "accepts a minimal valid Composition" do
    expect(described_class.call(base_payload)).to be_valid
  end

  it "rejects a missing status" do
    result = described_class.call(base_payload.except("status"))
    expect(result).not_to be_valid
    expect(result.issues.map { |i| i[:expression] }.flatten).to include("Composition.status")
  end

  it "rejects an invalid status" do
    result = described_class.call(base_payload.merge("status" => "draft"))
    expect(result).not_to be_valid
  end

  it "requires type, title, and date" do
    %w[type title date].each do |field|
      expect(described_class.call(base_payload.except(field))).not_to be_valid
    end
  end

  it "rejects a non-ISO8601 date" do
    expect(described_class.call(base_payload.merge("date" => "not-a-date"))).not_to be_valid
  end

  it "requires at least one author" do
    expect(described_class.call(base_payload.except("author"))).not_to be_valid
    expect(described_class.call(base_payload.merge("author" => []))).not_to be_valid
  end
end
