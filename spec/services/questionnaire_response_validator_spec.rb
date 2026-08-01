require "rails_helper"

RSpec.describe QuestionnaireResponseValidator do
  let(:patient) do
    Patient.create!(id: SecureRandom.uuid, version_id: 1, last_updated: Time.current,
                    content: { "resourceType" => "Patient" })
  end

  def base_payload(**overrides)
    {
      "resourceType" => "QuestionnaireResponse",
      "identifier" => { "value" => "1311234567^P0001^R0001" },
      "questionnaire" => "http://example.org/Questionnaire/example|1.0.0",
      "status" => "completed",
      "subject" => { "reference" => "Patient/#{patient.id}" },
      "authored" => "2026-07-29T10:00:00+09:00",
      "author" => { "reference" => "Practitioner/unknown" },
      "item" => [{ "linkId" => "q1", "answer" => [{ "valueString" => "腹痛" }] }]
    }.merge(overrides)
  end

  def diagnostics(result)
    result.issues.map { |issue| issue[:diagnostics] }.join("\n")
  end

  it "accepts a minimal valid QuestionnaireResponse" do
    expect(described_class.call(base_payload)).to be_valid
  end

  describe "required elements" do
    it "requires identifier, questionnaire, status, subject, authored, and author" do
      %w[identifier questionnaire status subject authored author].each do |field|
        expect(described_class.call(base_payload.except(field))).not_to be_valid,
                                                                        "expected #{field} to be required"
      end
    end
  end

  describe "status" do
    it "rejects a status outside questionnaire-answers-status" do
      expect(described_class.call(base_payload("status" => "final"))).not_to be_valid
    end

    it "accepts the three JASPEHR lifecycle values" do
      %w[completed amended stopped].each do |status|
        expect(described_class.call(base_payload("status" => status))).to be_valid
      end
    end
  end

  describe "identifier" do
    it "requires three non-empty caret-separated parts" do
      expect(described_class.call(base_payload("identifier" => { "value" => "1311234567" }))).not_to be_valid
      expect(described_class.call(base_payload("identifier" => { "value" => "1311234567^P0001" }))).not_to be_valid
      expect(described_class.call(base_payload("identifier" => { "value" => "1311234567^^R0001" }))).not_to be_valid
    end
  end

  describe "questionnaire" do
    it "rejects a value that is not an absolute canonical URL" do
      result = described_class.call(base_payload("questionnaire" => "Questionnaire/123"))

      expect(result).not_to be_valid
      expect(diagnostics(result)).to include("absolute canonical URL")
    end
  end

  describe "subject" do
    it "rejects a reference to a type other than Patient" do
      expect(described_class.call(base_payload("subject" => { "reference" => "Group/1" }))).not_to be_valid
    end

    it "rejects a Patient that does not exist" do
      expect(described_class.call(base_payload("subject" => { "reference" => "Patient/nope" }))).not_to be_valid
    end
  end

  describe "author" do
    it "accepts a contained reference" do
      expect(described_class.call(base_payload("author" => { "reference" => "#practitioner" }))).to be_valid
    end

    it "rejects a reference to another resource type" do
      expect(described_class.call(base_payload("author" => { "reference" => "Organization/1" }))).not_to be_valid
    end
  end

  describe "JP eCS institution number extension" do
    def with_institution_number(value)
      base_payload("extension" => [{
                     "url" => "http://jpfhir.jp/fhir/clins/Extension/StructureDefinition/JP_eCS_InstitutionNumber",
                     "valueIdentifier" => { "value" => value }
                   }])
    end

    it "accepts a well-formed 10-digit number" do
      expect(described_class.call(with_institution_number("1311234567"))).to be_valid
    end

    it "rejects a wrong length, a bad prefecture, or a bad fee schedule class" do
      ["131123456", "13112345678", "9311234567", "1341234567", "13X1234567"].each do |value|
        expect(described_class.call(with_institution_number(value))).not_to be_valid,
                                                                            "expected '#{value}' to be rejected"
      end
    end

    it "ignores other extensions" do
      payload = base_payload("extension" => [{ "url" => "http://example.org/other", "valueString" => "x" }])
      expect(described_class.call(payload)).to be_valid
    end
  end

  describe "jsr-1" do
    it "rejects a linkId outside the charset, at any depth" do
      payload = base_payload("item" => [
                               { "linkId" => "group1",
                                 "item" => [{ "linkId" => "設問1", "answer" => [{ "valueString" => "x" }] }] }
                             ])

      result = described_class.call(payload)
      expect(result).not_to be_valid
      expect(diagnostics(result)).to include("jsr-1")
    end

    it "reaches items nested under an answer" do
      payload = base_payload("item" => [
                               { "linkId" => "q1",
                                 "answer" => [{ "valueString" => "yes",
                                                "item" => [{ "linkId" => "設問2" }] }] }
                             ])

      result = described_class.call(payload)
      expect(result).not_to be_valid
      expect(diagnostics(result)).to include("jsr-1")
    end
  end

  it "rejects a non-ISO8601 authored" do
    expect(described_class.call(base_payload("authored" => "not-a-date"))).not_to be_valid
  end

  # FHIR dateTime accepts partial precision; the exhaustive cases live here since
  # every validator shares ResourceValidator#validate_datetime.
  describe "partial-precision authored (shared validate_datetime behavior)" do
    it "accepts date-only, year-month, and year values" do
      %w[2026-08-01 2026-08 2026].each do |value|
        expect(described_class.call(base_payload("authored" => value))).to be_valid
      end
    end

    it "rejects partial values that are not real calendar dates" do
      %w[2026-02-30 2026-13].each do |value|
        result = described_class.call(base_payload("authored" => value))
        expect(result).not_to be_valid
        expect(result.issues.map { |i| i[:diagnostics] }.join).to include("not a real calendar date")
      end
    end
  end
end
