require "rails_helper"

RSpec.describe Schedule do
  def build_schedule(content)
    described_class.new(
      id: SecureRandom.uuid,
      version_id: 1,
      content: content,
      last_updated: Time.current
    )
  end

  describe "#sync_search_fields!" do
    it "extracts active and both ends of the planning horizon" do
      schedule = build_schedule(
        "active" => true,
        "actor" => [{ "reference" => "Practitioner/pr1" }],
        "planningHorizon" => { "start" => "2026-09-01T00:00:00+09:00", "end" => "2026-09-30T23:59:59+09:00" }
      )

      schedule.sync_search_fields!

      expect(schedule.active).to be(true)
      expect(schedule.planning_horizon_start).to eq(Time.iso8601("2026-09-01T00:00:00+09:00"))
      expect(schedule.planning_horizon_end).to eq(Time.iso8601("2026-09-30T23:59:59+09:00"))
    end

    # actor is 1..* and searched by jsonb containment, so it must NOT acquire a
    # column -- a column would silently only hold the first actor.
    it "leaves actor in content only" do
      schedule = build_schedule(
        "actor" => [{ "reference" => "Practitioner/pr1" }, { "reference" => "Location/l1" }]
      )

      schedule.sync_search_fields!

      expect(described_class.column_names).not_to include("actor_reference")
      expect(schedule.content["actor"].size).to eq(2)
    end

    it "is nil-safe when fields are absent" do
      schedule = build_schedule({})

      expect { schedule.sync_search_fields! }.not_to raise_error
      expect(schedule.active).to be_nil
      expect(schedule.planning_horizon_start).to be_nil
    end
  end

  describe "#sync_tokens!" do
    it "emits a row per coding of every serviceCategory / serviceType / specialty concept" do
      schedule = build_schedule(
        "serviceCategory" => [
          { "coding" => [{ "system" => "http://example.org/cat", "code" => "17" },
                         { "system" => "http://example.org/local", "code" => "GEN" }] }
        ],
        "serviceType" => [
          { "coding" => [{ "system" => "http://example.org/type", "code" => "outpatient" }] },
          { "coding" => [{ "system" => "http://example.org/type", "code" => "vaccination" }] }
        ],
        "specialty" => [{ "coding" => [{ "system" => "http://snomed.info/sct", "code" => "419192003" }] }]
      )

      schedule.save!(validate: false)
      schedule.sync_tokens!

      expect(schedule.resource_tokens.where(param_name: "service-category").pluck(:code))
        .to contain_exactly("17", "GEN")
      expect(schedule.resource_tokens.where(param_name: "service-type").pluck(:code))
        .to contain_exactly("outpatient", "vaccination")
      expect(schedule.resource_tokens.where(param_name: "specialty").pluck(:system, :code))
        .to contain_exactly(["http://snomed.info/sct", "419192003"])
    end
  end
end
