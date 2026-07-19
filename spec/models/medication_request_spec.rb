require "rails_helper"

RSpec.describe MedicationRequest do
  def build_medication_request(content)
    described_class.new(
      id: SecureRandom.uuid,
      version_id: 1,
      content: content,
      last_updated: Time.current
    )
  end

  describe "#sync_search_fields!" do
    it "extracts status, intent, subject_reference, and authored_on" do
      medication_request = build_medication_request(
        "status" => "active",
        "intent" => "order",
        "subject" => { "reference" => "Patient/abc123" },
        "authoredOn" => "2026-07-19T10:00:00+09:00"
      )

      medication_request.sync_search_fields!

      expect(medication_request.status).to eq("active")
      expect(medication_request.intent).to eq("order")
      expect(medication_request.subject_reference).to eq("Patient/abc123")
      expect(medication_request.authored_on).to eq(Time.iso8601("2026-07-19T10:00:00+09:00"))
    end

    it "extracts medication_code and medication_text from medicationCodeableConcept" do
      medication_request = build_medication_request(
        "medicationCodeableConcept" => {
          "coding" => [
            { "system" => "urn:oid:1.2.392.100495.20.2.74", "code" => "620004422", "display" => "アムロジピン錠5mg" }
          ],
          "text" => "アムロジピン錠5mg"
        }
      )

      medication_request.sync_search_fields!

      expect(medication_request.medication_code).to eq("620004422")
      expect(medication_request.medication_text).to include("アムロジピン錠5mg")
    end

    it "is nil-safe when fields are absent" do
      medication_request = build_medication_request({})

      expect { medication_request.sync_search_fields! }.not_to raise_error
      expect(medication_request.authored_on).to be_nil
      expect(medication_request.medication_code).to be_nil
      expect(medication_request.subject_reference).to be_nil
    end
  end
end
