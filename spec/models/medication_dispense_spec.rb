require "rails_helper"

RSpec.describe MedicationDispense do
  def build_dispense(content)
    described_class.new(
      id: SecureRandom.uuid,
      version_id: 1,
      content: content,
      last_updated: Time.current
    )
  end

  describe "#sync_search_fields!" do
    it "extracts status, subject, medication code/text, context, and whenHandedOver" do
      dispense = build_dispense(
        "status" => "completed",
        "subject" => { "reference" => "Patient/abc123" },
        "context" => { "reference" => "Encounter/enc1" },
        "whenHandedOver" => "2026-07-19T10:00:00+09:00",
        "medicationCodeableConcept" => {
          "coding" => [{ "code" => "620004422", "display" => "アムロジピン錠5mg" }],
          "text" => "アムロジピン錠5mg"
        }
      )

      dispense.sync_search_fields!

      expect(dispense.status).to eq("completed")
      expect(dispense.subject_reference).to eq("Patient/abc123")
      expect(dispense.context_reference).to eq("Encounter/enc1")
      expect(dispense.when_handed_over).to eq(Time.iso8601("2026-07-19T10:00:00+09:00"))
      expect(dispense.medication_code).to eq("620004422")
      expect(dispense.medication_text).to include("アムロジピン錠5mg")
    end

    it "is nil-safe when fields are absent" do
      dispense = build_dispense({})

      expect { dispense.sync_search_fields! }.not_to raise_error
      expect(dispense.when_handed_over).to be_nil
      expect(dispense.subject_reference).to be_nil
    end
  end
end
