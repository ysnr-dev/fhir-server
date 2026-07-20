require "rails_helper"

RSpec.describe AllergyIntolerance do
  def build_allergy_intolerance(content)
    described_class.new(
      id: SecureRandom.uuid,
      version_id: 1,
      content: content,
      last_updated: Time.current
    )
  end

  describe "#sync_search_fields!" do
    it "extracts status, type, category, criticality, code, patient, and recorded date" do
      allergy = build_allergy_intolerance(
        "clinicalStatus" => { "coding" => [{ "code" => "active" }] },
        "verificationStatus" => { "coding" => [{ "code" => "confirmed" }] },
        "type" => "allergy",
        "category" => ["medication", "food"],
        "criticality" => "high",
        "code" => { "coding" => [{ "code" => "7980", "display" => "Penicillin" }] },
        "patient" => { "reference" => "Patient/abc123" },
        "recordedDate" => "2026-07-19T10:00:00+09:00"
      )

      allergy.sync_search_fields!

      expect(allergy.clinical_status).to eq("active")
      expect(allergy.verification_status).to eq("confirmed")
      expect(allergy.type_code).to eq("allergy")
      expect(allergy.category_code).to eq("medication")
      expect(allergy.criticality).to eq("high")
      expect(allergy.code_value).to eq("7980")
      expect(allergy.code_text).to eq("Penicillin")
      expect(allergy.patient_reference).to eq("Patient/abc123")
      expect(allergy.recorded_time).to eq(Time.iso8601("2026-07-19T10:00:00+09:00"))
    end

    it "is nil-safe when fields are absent" do
      allergy = build_allergy_intolerance({})

      expect { allergy.sync_search_fields! }.not_to raise_error
      expect(allergy.category_code).to be_nil
      expect(allergy.patient_reference).to be_nil
    end
  end
end
