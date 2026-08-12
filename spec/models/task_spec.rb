require "rails_helper"

RSpec.describe Task do
  def build_task(content)
    described_class.new(
      id: SecureRandom.uuid,
      version_id: 1,
      content: content,
      last_updated: Time.current
    )
  end

  describe "#sync_search_fields!" do
    it "extracts the workflow columns, references, and both timestamps" do
      task = build_task(
        "status" => "in-progress",
        "intent" => "order",
        "priority" => "urgent",
        "businessStatus" => {
          "coding" => [{ "system" => "http://example.org/lab", "code" => "collected" }],
          "text" => "検体採取済"
        },
        "groupIdentifier" => { "system" => "http://example.org/order-group", "value" => "ORD-1" },
        "performerType" => [{ "coding" => [{ "code" => "nurse" }] }],
        "code" => { "coding" => [{ "code" => "fulfill", "display" => "実施" }], "text" => "検査の実施" },
        "for" => { "reference" => "Patient/p1" },
        "encounter" => { "reference" => "Encounter/e1" },
        "requester" => { "reference" => "Practitioner/pr1" },
        "owner" => { "reference" => "Practitioner/pr2" },
        "focus" => { "reference" => "ServiceRequest/sr1" },
        "authoredOn" => "2026-08-12T09:00:00+09:00",
        "lastModified" => "2026-08-12T10:30:00+09:00",
        "executionPeriod" => { "start" => "2026-08-12T09:30:00+09:00", "end" => "2026-08-12T10:30:00+09:00" }
      )

      task.sync_search_fields!

      expect(task.status).to eq("in-progress")
      expect(task.intent).to eq("order")
      expect(task.priority).to eq("urgent")
      expect(task.business_status).to eq("collected")
      expect(task.group_identifier).to eq("ORD-1")
      expect(task.performer_type).to eq("nurse")
      expect(task.code).to eq("fulfill")
      expect(task.code_text).to eq("検査の実施 実施")
      expect(task.for_reference).to eq("Patient/p1")
      expect(task.encounter_reference).to eq("Encounter/e1")
      expect(task.requester_reference).to eq("Practitioner/pr1")
      expect(task.owner_reference).to eq("Practitioner/pr2")
      expect(task.focus_reference).to eq("ServiceRequest/sr1")
      expect(task.authored_on).to eq(Time.iso8601("2026-08-12T09:00:00+09:00"))
      expect(task.last_modified).to eq(Time.iso8601("2026-08-12T10:30:00+09:00"))
      expect(task.execution_period_start).to eq(Time.iso8601("2026-08-12T09:30:00+09:00"))
      expect(task.execution_period_end).to eq(Time.iso8601("2026-08-12T10:30:00+09:00"))
    end

    # basedOn/partOf are 0..* and searched by jsonb containment, so they must
    # NOT acquire a column -- a column would silently only hold the first entry.
    it "leaves basedOn and partOf in content only" do
      task = build_task(
        "status" => "requested",
        "intent" => "order",
        "basedOn" => [{ "reference" => "ServiceRequest/sr1" }, { "reference" => "ServiceRequest/sr2" }],
        "partOf" => [{ "reference" => "Task/t1" }]
      )

      task.sync_search_fields!

      expect(described_class.column_names).not_to include("based_on_reference", "part_of_reference")
      expect(task.content["basedOn"].size).to eq(2)
    end

    it "is nil-safe when fields are absent" do
      task = build_task({})

      expect { task.sync_search_fields! }.not_to raise_error
      expect(task.status).to be_nil
      expect(task.business_status).to be_nil
      expect(task.for_reference).to be_nil
      expect(task.execution_period_end).to be_nil
    end
  end

  describe "#sync_tokens!" do
    it "emits rows for status, intent, priority, businessStatus, groupIdentifier, performerType, and every code coding" do
      task = build_task(
        "status" => "in-progress",
        "intent" => "order",
        "priority" => "urgent",
        "businessStatus" => { "coding" => [{ "system" => "http://example.org/lab", "code" => "collected" }] },
        "groupIdentifier" => { "system" => "http://example.org/order-group", "value" => "ORD-1" },
        "performerType" => [
          { "coding" => [{ "system" => "http://example.org/role", "code" => "nurse" }] },
          { "coding" => [{ "system" => "http://example.org/role", "code" => "tech" }] }
        ],
        "code" => {
          "coding" => [
            { "system" => "http://hl7.org/fhir/CodeSystem/task-code", "code" => "fulfill" },
            { "system" => "http://example.org/local", "code" => "LAB-EXEC" }
          ]
        }
      )

      task.save!(validate: false)
      task.sync_tokens!

      expect(task.resource_tokens.where(param_name: "status").pluck(:code)).to eq(["in-progress"])
      expect(task.resource_tokens.where(param_name: "priority").pluck(:code)).to eq(["urgent"])
      expect(task.resource_tokens.where(param_name: "business-status").pluck(:system, :code))
        .to contain_exactly(["http://example.org/lab", "collected"])
      # groupIdentifier is an Identifier: its system/value pair becomes the token.
      expect(task.resource_tokens.where(param_name: "group-identifier").pluck(:system, :code))
        .to contain_exactly(["http://example.org/order-group", "ORD-1"])
      expect(task.resource_tokens.where(param_name: "performer").pluck(:code))
        .to contain_exactly("nurse", "tech")
      expect(task.resource_tokens.where(param_name: "code").pluck(:code))
        .to contain_exactly("fulfill", "LAB-EXEC")
    end
  end
end
