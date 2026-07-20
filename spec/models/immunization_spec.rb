require "rails_helper"

RSpec.describe Immunization do
  def build_immunization(content)
    described_class.new(
      id: SecureRandom.uuid,
      version_id: 1,
      content: content,
      last_updated: Time.current
    )
  end

  describe "#sync_search_fields!" do
    it "extracts status, vaccine code, patient, occurrence time, and lot number" do
      immunization = build_immunization(
        "status" => "completed",
        "vaccineCode" => { "coding" => [{ "code" => "49281-0215-88", "display" => "COVID-19 vaccine" }] },
        "patient" => { "reference" => "Patient/abc123" },
        "occurrenceDateTime" => "2026-07-19T10:00:00+09:00",
        "lotNumber" => "LOT-123"
      )

      immunization.sync_search_fields!

      expect(immunization.status).to eq("completed")
      expect(immunization.vaccine_code).to eq("49281-0215-88")
      expect(immunization.vaccine_text).to eq("COVID-19 vaccine")
      expect(immunization.patient_reference).to eq("Patient/abc123")
      expect(immunization.occurrence_time).to eq(Time.iso8601("2026-07-19T10:00:00+09:00"))
      expect(immunization.lot_number).to eq("LOT-123")
    end

    it "is nil-safe when fields are absent" do
      immunization = build_immunization({})

      expect { immunization.sync_search_fields! }.not_to raise_error
      expect(immunization.vaccine_code).to be_nil
      expect(immunization.patient_reference).to be_nil
    end
  end
end
