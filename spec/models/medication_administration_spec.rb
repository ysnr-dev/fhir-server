require "rails_helper"

RSpec.describe MedicationAdministration do
  def build_administration(content)
    described_class.new(
      id: SecureRandom.uuid,
      version_id: 1,
      content: content,
      last_updated: Time.current
    )
  end

  describe "#sync_search_fields!" do
    it "extracts status, subject, medication code/text, context, request, and effective time" do
      administration = build_administration(
        "status" => "completed",
        "subject" => { "reference" => "Patient/abc123" },
        "context" => { "reference" => "Encounter/enc1" },
        "request" => { "reference" => "MedicationRequest/mr1" },
        "effectiveDateTime" => "2026-07-19T10:00:00+09:00",
        "medicationCodeableConcept" => {
          "coding" => [{ "code" => "620004422", "display" => "アムロジピン錠5mg" }],
          "text" => "アムロジピン錠5mg"
        }
      )

      administration.sync_search_fields!

      expect(administration.status).to eq("completed")
      expect(administration.subject_reference).to eq("Patient/abc123")
      expect(administration.context_reference).to eq("Encounter/enc1")
      expect(administration.request_reference).to eq("MedicationRequest/mr1")
      expect(administration.effective_time).to eq(Time.iso8601("2026-07-19T10:00:00+09:00"))
      expect(administration.medication_code).to eq("620004422")
    end

    it "is nil-safe when fields are absent" do
      administration = build_administration({})

      expect { administration.sync_search_fields! }.not_to raise_error
      expect(administration.effective_time).to be_nil
      expect(administration.request_reference).to be_nil
    end
  end
end
