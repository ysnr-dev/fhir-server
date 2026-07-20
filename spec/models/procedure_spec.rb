require "rails_helper"

RSpec.describe Procedure do
  def build_procedure(content)
    described_class.new(
      id: SecureRandom.uuid,
      version_id: 1,
      content: content,
      last_updated: Time.current
    )
  end

  describe "#sync_search_fields!" do
    it "extracts status, category, code, references, and performed time" do
      procedure = build_procedure(
        "status" => "completed",
        "category" => { "coding" => [{ "code" => "387713003" }] },
        "code" => { "coding" => [{ "code" => "80146002", "display" => "Appendectomy" }] },
        "subject" => { "reference" => "Patient/abc123" },
        "encounter" => { "reference" => "Encounter/enc1" },
        "performedDateTime" => "2026-07-19T10:00:00+09:00"
      )

      procedure.sync_search_fields!

      expect(procedure.status).to eq("completed")
      expect(procedure.category_code).to eq("387713003")
      expect(procedure.code_value).to eq("80146002")
      expect(procedure.code_text).to eq("Appendectomy")
      expect(procedure.subject_reference).to eq("Patient/abc123")
      expect(procedure.encounter_reference).to eq("Encounter/enc1")
      expect(procedure.performed_time).to eq(Time.iso8601("2026-07-19T10:00:00+09:00"))
    end

    it "is nil-safe when fields are absent" do
      procedure = build_procedure({})

      expect { procedure.sync_search_fields! }.not_to raise_error
      expect(procedure.performed_time).to be_nil
      expect(procedure.subject_reference).to be_nil
    end
  end
end
