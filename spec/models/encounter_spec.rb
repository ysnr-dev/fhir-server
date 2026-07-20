require "rails_helper"

RSpec.describe Encounter do
  def build_encounter(content)
    described_class.new(
      id: SecureRandom.uuid,
      version_id: 1,
      content: content,
      last_updated: Time.current
    )
  end

  describe "#sync_search_fields!" do
    it "extracts status, class code, subject_reference, and period start" do
      encounter = build_encounter(
        "status" => "finished",
        "class" => { "code" => "AMB" },
        "subject" => { "reference" => "Patient/abc123" },
        "period" => { "start" => "2026-07-19T09:00:00+09:00" }
      )

      encounter.sync_search_fields!

      expect(encounter.status).to eq("finished")
      expect(encounter.class_code).to eq("AMB")
      expect(encounter.subject_reference).to eq("Patient/abc123")
      expect(encounter.period_start).to eq(Time.iso8601("2026-07-19T09:00:00+09:00"))
    end

    it "is nil-safe when fields are absent" do
      encounter = build_encounter({})

      expect { encounter.sync_search_fields! }.not_to raise_error
      expect(encounter.class_code).to be_nil
      expect(encounter.period_start).to be_nil
    end
  end
end
