require "rails_helper"

RSpec.describe SlotValidator do
  def payload(overrides = {})
    {
      "resourceType" => "Slot",
      "status" => "free",
      "schedule" => { "reference" => "Schedule/sch1" },
      "start" => "2026-09-01T09:00:00+09:00",
      "end" => "2026-09-01T09:30:00+09:00"
    }.deep_merge(overrides.deep_stringify_keys)
  end

  it "is valid for a well-formed slot" do
    result = described_class.call(payload)

    expect(result).to be_valid
    expect(result.warnings).to be_empty
  end

  describe "status" do
    it "rejects a missing status" do
      result = described_class.call(payload.except("status"))

      expect(result).not_to be_valid
      expect(result.errors.first[:code]).to eq("required")
    end

    it "rejects a status outside the slot-status ValueSet" do
      # "booked" is an Appointment status, not a Slot one -- the slot equivalent is "busy".
      result = described_class.call(payload("status" => "booked"))

      expect(result).not_to be_valid
      expect(result.errors.first[:code]).to eq("value")
    end

    it "accepts busy-tentative for a slot held by a pending appointment" do
      result = described_class.call(payload("status" => "busy-tentative"))

      expect(result).to be_valid
    end
  end

  describe "schedule" do
    it "rejects a slot with no schedule" do
      result = described_class.call(payload.except("schedule"))

      expect(result).not_to be_valid
      expect(result.errors.first[:expression]).to eq(["Slot.schedule.reference"])
    end

    it "rejects a schedule reference pointing at another resource type" do
      result = described_class.call(payload.merge("schedule" => { "reference" => "Location/l1" }))

      expect(result).not_to be_valid
      expect(result.errors.first[:code]).to eq("value")
    end

    # Structural only: a Slot is routinely written in the same transaction Bundle
    # as its Schedule, so an existence check would reject the ordinary bulk load.
    it "accepts a schedule reference that does not resolve to a stored Schedule" do
      result = described_class.call(payload.merge("schedule" => { "reference" => "Schedule/does-not-exist" }))

      expect(result).to be_valid
    end
  end

  describe "start / end" do
    it "rejects a missing start" do
      result = described_class.call(payload.except("start"))

      expect(result).not_to be_valid
      expect(result.errors.first[:code]).to eq("required")
    end

    it "rejects a missing end" do
      result = described_class.call(payload.except("end"))

      expect(result).not_to be_valid
      expect(result.errors.first[:code]).to eq("required")
    end

    # start/end are `instant`, not `dateTime`: partial precision and a missing
    # timezone are both invalid, and the latter would silently shift the slot by
    # the server's UTC offset.
    it "rejects a date-only start" do
      result = described_class.call(payload("start" => "2026-09-01"))

      expect(result).not_to be_valid
      expect(result.errors.first[:diagnostics]).to include("instant")
    end

    it "rejects an instant with no timezone offset" do
      result = described_class.call(payload("start" => "2026-09-01T09:00:00"))

      expect(result).not_to be_valid
      expect(result.errors.first[:diagnostics]).to include("instant")
    end

    it "accepts a UTC instant" do
      result = described_class.call(payload("start" => "2026-09-01T00:00:00Z", "end" => "2026-09-01T00:30:00Z"))

      expect(result).to be_valid
    end

    it "rejects a well-shaped but non-existent instant" do
      result = described_class.call(payload("start" => "2026-02-30T09:00:00+09:00"))

      expect(result).not_to be_valid
    end

    it "rejects an end at or before the start" do
      result = described_class.call(payload("end" => "2026-09-01T09:00:00+09:00"))

      expect(result).not_to be_valid
      expect(result.errors.first[:code]).to eq("invariant")
    end
  end

  describe "overbooked" do
    it "rejects a non-boolean overbooked" do
      result = described_class.call(payload("overbooked" => "false"))

      expect(result).not_to be_valid
      expect(result.errors.first[:code]).to eq("value")
    end
  end
end
