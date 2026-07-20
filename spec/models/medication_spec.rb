require "rails_helper"

RSpec.describe Medication do
  def build_medication(content)
    described_class.new(
      id: SecureRandom.uuid,
      version_id: 1,
      content: content,
      last_updated: Time.current
    )
  end

  describe "#sync_search_fields!" do
    it "extracts status, medication code/text, form, and manufacturer" do
      medication = build_medication(
        "status" => "active",
        "code" => {
          "coding" => [{ "code" => "620004422", "display" => "アムロジピン錠5mg" }],
          "text" => "アムロジピン錠5mg"
        },
        "form" => { "coding" => [{ "code" => "10" }] },
        "manufacturer" => { "reference" => "Organization/org1" }
      )

      medication.sync_search_fields!

      expect(medication.status).to eq("active")
      expect(medication.medication_code).to eq("620004422")
      expect(medication.medication_text).to include("アムロジピン錠5mg")
      expect(medication.form_code).to eq("10")
      expect(medication.manufacturer_reference).to eq("Organization/org1")
    end

    it "is nil-safe when fields are absent" do
      medication = build_medication({})

      expect { medication.sync_search_fields! }.not_to raise_error
      expect(medication.medication_code).to be_nil
      expect(medication.form_code).to be_nil
      expect(medication.manufacturer_reference).to be_nil
    end
  end
end
