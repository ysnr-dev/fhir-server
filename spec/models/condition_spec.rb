require "rails_helper"

RSpec.describe Condition do
  def build_condition(content)
    described_class.new(
      id: SecureRandom.uuid,
      version_id: 1,
      content: content,
      last_updated: Time.current
    )
  end

  describe "#sync_search_fields!" do
    it "extracts status, category, severity, code, references, and dates" do
      condition = build_condition(
        "clinicalStatus" => { "coding" => [{ "code" => "active" }] },
        "verificationStatus" => { "coding" => [{ "code" => "confirmed" }] },
        "category" => [{ "coding" => [{ "code" => "encounter-diagnosis" }] }],
        "severity" => { "coding" => [{ "code" => "255604002" }] },
        "code" => { "coding" => [{ "code" => "J20.9", "display" => "急性気管支炎" }] },
        "subject" => { "reference" => "Patient/abc123" },
        "encounter" => { "reference" => "Encounter/enc1" },
        "onsetDateTime" => "2026-07-19T10:00:00+09:00",
        "recordedDate" => "2026-07-18T09:00:00+09:00"
      )

      condition.sync_search_fields!

      expect(condition.clinical_status).to eq("active")
      expect(condition.verification_status).to eq("confirmed")
      expect(condition.category_code).to eq("encounter-diagnosis")
      expect(condition.severity_code).to eq("255604002")
      expect(condition.code_value).to eq("J20.9")
      expect(condition.code_text).to eq("急性気管支炎")
      expect(condition.subject_reference).to eq("Patient/abc123")
      expect(condition.encounter_reference).to eq("Encounter/enc1")
      expect(condition.onset_time).to eq(Time.iso8601("2026-07-19T10:00:00+09:00"))
      expect(condition.recorded_time).to eq(Time.iso8601("2026-07-18T09:00:00+09:00"))
    end

    it "is nil-safe when fields are absent" do
      condition = build_condition({})

      expect { condition.sync_search_fields! }.not_to raise_error
      expect(condition.clinical_status).to be_nil
      expect(condition.subject_reference).to be_nil
    end
  end
end
