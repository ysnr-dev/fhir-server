require "rails_helper"

RSpec.describe QuestionnaireResponse do
  def build_response(content)
    described_class.new(
      id: SecureRandom.uuid,
      version_id: 1,
      content: content,
      last_updated: Time.current
    )
  end

  describe "#sync_search_fields!" do
    it "extracts the canonical, status, references, and authored time" do
      response = build_response(
        "questionnaire" => "http://example.org/Questionnaire/example|1.0.0",
        "status" => "completed",
        "subject" => { "reference" => "Patient/abc123" },
        "encounter" => { "reference" => "Encounter/enc1" },
        "author" => { "reference" => "Practitioner/pr1" },
        "source" => { "reference" => "Patient/abc123" },
        "authored" => "2026-07-29T10:00:00+09:00"
      )

      response.sync_search_fields!

      expect(response.questionnaire_canonical).to eq("http://example.org/Questionnaire/example|1.0.0")
      expect(response.status).to eq("completed")
      expect(response.subject_reference).to eq("Patient/abc123")
      expect(response.encounter_reference).to eq("Encounter/enc1")
      expect(response.author_reference).to eq("Practitioner/pr1")
      expect(response.source_reference).to eq("Patient/abc123")
      expect(response.authored).to eq(Time.iso8601("2026-07-29T10:00:00+09:00"))
    end

    it "is nil-safe when fields are absent" do
      response = build_response({})

      expect { response.sync_search_fields! }.not_to raise_error
      expect(response.questionnaire_canonical).to be_nil
      expect(response.subject_reference).to be_nil
    end
  end

  describe "#sync_identifiers!" do
    it "extracts the single (1..1) identifier object" do
      response = build_response(
        "identifier" => { "system" => "http://example.org/questionnaire-response", "value" => "1311234567^P0001^R0001" }
      )

      response.save!(validate: false)
      response.sync_identifiers!

      expect(response.resource_identifiers.pluck(:system, :value))
        .to contain_exactly(["http://example.org/questionnaire-response", "1311234567^P0001^R0001"])
    end
  end
end
