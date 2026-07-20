require "rails_helper"

RSpec.describe DiagnosticReport do
  def build_report(content)
    described_class.new(
      id: SecureRandom.uuid,
      version_id: 1,
      content: content,
      last_updated: Time.current
    )
  end

  describe "#sync_search_fields!" do
    it "extracts status, category, code value/text, subject, encounter, and effective time" do
      report = build_report(
        "status" => "final",
        "category" => [{ "coding" => [{ "code" => "LAB" }] }],
        "code" => {
          "coding" => [{ "code" => "58410-2", "display" => "CBC panel" }],
          "text" => "血算"
        },
        "subject" => { "reference" => "Patient/abc123" },
        "encounter" => { "reference" => "Encounter/enc1" },
        "effectiveDateTime" => "2026-07-19T10:00:00+09:00"
      )

      report.sync_search_fields!

      expect(report.status).to eq("final")
      expect(report.category_code).to eq("LAB")
      expect(report.code_value).to eq("58410-2")
      expect(report.code_text).to include("血算")
      expect(report.subject_reference).to eq("Patient/abc123")
      expect(report.encounter_reference).to eq("Encounter/enc1")
      expect(report.effective_time).to eq(Time.iso8601("2026-07-19T10:00:00+09:00"))
    end

    it "is nil-safe when fields are absent" do
      report = build_report({})

      expect { report.sync_search_fields! }.not_to raise_error
      expect(report.effective_time).to be_nil
      expect(report.category_code).to be_nil
    end
  end
end
