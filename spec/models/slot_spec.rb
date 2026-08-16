require "rails_helper"

RSpec.describe Slot do
  def build_slot(content)
    described_class.new(
      id: SecureRandom.uuid,
      version_id: 1,
      content: content,
      last_updated: Time.current
    )
  end

  describe "#sync_search_fields!" do
    it "extracts the status, schedule reference, appointment type, and start" do
      slot = build_slot(
        "status" => "free",
        "schedule" => { "reference" => "Schedule/sch1" },
        "appointmentType" => { "coding" => [{ "code" => "ROUTINE" }] },
        "start" => "2026-09-01T09:00:00+09:00",
        "end" => "2026-09-01T09:30:00+09:00"
      )

      slot.sync_search_fields!

      expect(slot.status).to eq("free")
      expect(slot.schedule_reference).to eq("Schedule/sch1")
      expect(slot.appointment_type).to eq("ROUTINE")
      expect(slot.start_time).to eq(Time.iso8601("2026-09-01T09:00:00+09:00"))
    end

    # R4 gives Slot no `end` search parameter, so Slot.end stays in content only.
    it "does not extract end into a column" do
      expect(described_class.column_names).not_to include("end_time")
    end

    it "is nil-safe when fields are absent" do
      slot = build_slot({})

      expect { slot.sync_search_fields! }.not_to raise_error
      expect(slot.status).to be_nil
      expect(slot.start_time).to be_nil
    end
  end

  describe "#sync_tokens!" do
    it "emits rows for status, appointmentType, and every service concept coding" do
      slot = build_slot(
        "status" => "busy-tentative",
        "appointmentType" => {
          "coding" => [{ "system" => "http://terminology.hl7.org/CodeSystem/v2-0276", "code" => "ROUTINE" }]
        },
        "serviceCategory" => [{ "coding" => [{ "system" => "http://example.org/cat", "code" => "17" }] }],
        "serviceType" => [{ "coding" => [{ "system" => "http://example.org/type", "code" => "outpatient" }] }],
        "specialty" => [{ "coding" => [{ "system" => "http://snomed.info/sct", "code" => "419192003" }] }]
      )

      slot.save!(validate: false)
      slot.sync_tokens!

      expect(slot.resource_tokens.where(param_name: "status").pluck(:code)).to eq(["busy-tentative"])
      expect(slot.resource_tokens.where(param_name: "appointment-type").pluck(:system, :code))
        .to contain_exactly(["http://terminology.hl7.org/CodeSystem/v2-0276", "ROUTINE"])
      expect(slot.resource_tokens.where(param_name: "service-category").pluck(:code)).to eq(["17"])
      expect(slot.resource_tokens.where(param_name: "service-type").pluck(:code)).to eq(["outpatient"])
      expect(slot.resource_tokens.where(param_name: "specialty").pluck(:code)).to eq(["419192003"])
    end
  end
end
