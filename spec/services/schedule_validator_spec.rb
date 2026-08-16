require "rails_helper"

RSpec.describe ScheduleValidator do
  def payload(overrides = {})
    {
      "resourceType" => "Schedule",
      "active" => true,
      "actor" => [{ "reference" => "Practitioner/pr1" }],
      "planningHorizon" => { "start" => "2026-09-01T00:00:00+09:00", "end" => "2026-09-30T23:59:59+09:00" }
    }.deep_merge(overrides.deep_stringify_keys)
  end

  it "is valid for a well-formed schedule" do
    result = described_class.call(payload)

    expect(result).to be_valid
    expect(result.warnings).to be_empty
  end

  describe "actor" do
    it "rejects a schedule with no actor" do
      result = described_class.call(payload.except("actor"))

      expect(result).not_to be_valid
      expect(result.errors.first[:code]).to eq("required")
      expect(result.errors.first[:diagnostics]).to include("1..*")
    end

    it "rejects an empty actor array" do
      result = described_class.call(payload("actor" => []))

      expect(result).not_to be_valid
      expect(result.errors.first[:code]).to eq("required")
    end

    it "rejects a non-array actor, which `actor` search could not match" do
      result = described_class.call(payload("actor" => { "reference" => "Practitioner/pr1" }))

      expect(result).not_to be_valid
      expect(result.errors.first[:code]).to eq("structure")
    end

    it "rejects an actor entry with no reference" do
      result = described_class.call(payload("actor" => [{ "display" => "内科外来" }]))

      expect(result).not_to be_valid
      expect(result.errors.first[:expression]).to eq(["Schedule.actor[0].reference"])
    end

    it "accepts an actor that is a Location rather than a Practitioner" do
      result = described_class.call(payload("actor" => [{ "reference" => "Location/l1" }]))

      expect(result).to be_valid
    end
  end

  describe "active" do
    it "rejects a non-boolean active" do
      result = described_class.call(payload("active" => "true"))

      expect(result).not_to be_valid
      expect(result.errors.first[:code]).to eq("value")
    end
  end

  describe "planningHorizon" do
    it "accepts a schedule with no planning horizon" do
      result = described_class.call(payload.except("planningHorizon"))

      expect(result).to be_valid
    end

    it "rejects a malformed planningHorizon.start" do
      result = described_class.call(payload.merge("planningHorizon" => { "start" => "not-a-date" }))

      expect(result).not_to be_valid
      expect(result.errors.first[:expression]).to eq(["Schedule.planningHorizon.start"])
    end

    # An inverted horizon matches nothing under the period semantics of `date`,
    # which looks like "no schedules" rather than "bad data".
    it "rejects a horizon that ends before it starts" do
      result = described_class.call(
        payload.merge("planningHorizon" => { "start" => "2026-09-30T00:00:00+09:00",
                                             "end" => "2026-09-01T00:00:00+09:00" })
      )

      expect(result).not_to be_valid
      expect(result.errors.first[:code]).to eq("invariant")
    end

    it "accepts an open-ended horizon" do
      result = described_class.call(payload.merge("planningHorizon" => { "start" => "2026-09-01T00:00:00+09:00" }))

      expect(result).to be_valid
    end
  end
end
