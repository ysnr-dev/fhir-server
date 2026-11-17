require "rails_helper"

RSpec.describe FamilyMemberHistory do
  def build_history(content)
    described_class.new(
      id: SecureRandom.uuid,
      version_id: 1,
      content: content,
      last_updated: Time.current
    )
  end

  describe "#sync_search_fields!" do
    it "extracts status, relationship, sex, patient, date, and every condition's text" do
      history = build_history(
        "status" => "completed",
        "patient" => { "reference" => "Patient/abc123" },
        "date" => "2026-07-19T10:00:00+09:00",
        "relationship" => { "coding" => [{ "system" => "http://terminology.hl7.org/CodeSystem/v3-RoleCode", "code" => "MTH" }] },
        "sex" => { "coding" => [{ "system" => "http://hl7.org/fhir/administrative-gender", "code" => "female" }] },
        "condition" => [
          { "code" => { "coding" => [{ "code" => "E11", "display" => "Type 2 diabetes" }], "text" => "糖尿病" } },
          { "code" => { "text" => "難聴" } }
        ]
      )

      history.sync_search_fields!

      expect(history.status).to eq("completed")
      expect(history.relationship_code).to eq("MTH")
      expect(history.sex_code).to eq("female")
      expect(history.patient_reference).to eq("Patient/abc123")
      expect(history.recorded_time).to eq(Time.iso8601("2026-07-19T10:00:00+09:00"))
      expect(history.code_text).to eq("糖尿病 Type 2 diabetes 難聴")
    end

    it "is nil-safe when optional fields are absent" do
      history = build_history("status" => "health-unknown", "patient" => { "reference" => "Patient/abc123" })

      history.sync_search_fields!

      expect(history.sex_code).to be_nil
      expect(history.recorded_time).to be_nil
      expect(history.code_text).to be_nil
    end
  end
end
