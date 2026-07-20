require "rails_helper"

RSpec.describe Observation do
  def build_observation(content)
    described_class.new(
      id: SecureRandom.uuid,
      version_id: 1,
      content: content,
      last_updated: Time.current
    )
  end

  describe "#sync_search_fields!" do
    it "extracts status, category, code value/text, subject, encounter, and effective time" do
      observation = build_observation(
        "status" => "final",
        "category" => [{ "coding" => [{ "code" => "laboratory" }] }],
        "code" => {
          "coding" => [{ "code" => "718-7", "display" => "Hemoglobin" }],
          "text" => "ヘモグロビン"
        },
        "subject" => { "reference" => "Patient/abc123" },
        "encounter" => { "reference" => "Encounter/enc1" },
        "effectiveDateTime" => "2026-07-19T10:00:00+09:00"
      )

      observation.sync_search_fields!

      expect(observation.status).to eq("final")
      expect(observation.category_code).to eq("laboratory")
      expect(observation.code_value).to eq("718-7")
      expect(observation.code_text).to include("ヘモグロビン")
      expect(observation.subject_reference).to eq("Patient/abc123")
      expect(observation.encounter_reference).to eq("Encounter/enc1")
      expect(observation.effective_time).to eq(Time.iso8601("2026-07-19T10:00:00+09:00"))
    end

    it "is nil-safe when fields are absent" do
      observation = build_observation({})

      expect { observation.sync_search_fields! }.not_to raise_error
      expect(observation.effective_time).to be_nil
      expect(observation.category_code).to be_nil
      expect(observation.subject_reference).to be_nil
    end
  end
end
