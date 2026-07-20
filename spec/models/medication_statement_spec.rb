require "rails_helper"

RSpec.describe MedicationStatement do
  def build_statement(content)
    described_class.new(
      id: SecureRandom.uuid,
      version_id: 1,
      content: content,
      last_updated: Time.current
    )
  end

  describe "#sync_search_fields!" do
    it "extracts status, subject, medication code/text, context, and effective time" do
      statement = build_statement(
        "status" => "active",
        "subject" => { "reference" => "Patient/abc123" },
        "context" => { "reference" => "Encounter/enc1" },
        "effectiveDateTime" => "2026-07-19T10:00:00+09:00",
        "medicationCodeableConcept" => {
          "coding" => [{ "code" => "620004422", "display" => "アムロジピン錠5mg" }],
          "text" => "アムロジピン錠5mg"
        }
      )

      statement.sync_search_fields!

      expect(statement.status).to eq("active")
      expect(statement.subject_reference).to eq("Patient/abc123")
      expect(statement.context_reference).to eq("Encounter/enc1")
      expect(statement.effective_time).to eq(Time.iso8601("2026-07-19T10:00:00+09:00"))
      expect(statement.medication_code).to eq("620004422")
      expect(statement.medication_text).to include("アムロジピン錠5mg")
    end

    it "is nil-safe when fields are absent" do
      statement = build_statement({})

      expect { statement.sync_search_fields! }.not_to raise_error
      expect(statement.effective_time).to be_nil
      expect(statement.subject_reference).to be_nil
    end
  end
end
