require "rails_helper"

RSpec.describe Group do
  def build_group(content)
    described_class.new(
      id: SecureRandom.uuid,
      version_id: 1,
      content: content,
      last_updated: Time.current
    )
  end

  describe "#sync_search_fields!" do
    it "extracts type, actual, code, and managingEntity" do
      group = build_group(
        "type" => "person",
        "actual" => true,
        "code" => { "coding" => [{ "system" => "http://example.org/CodeSystem/cohort", "code" => "checkup-2026" }] },
        "managingEntity" => { "reference" => "Organization/o1" },
        "member" => [{ "entity" => { "reference" => "Patient/p1" } }]
      )

      group.sync_search_fields!

      # Group.type is stored as group_type -- a `type` column would trigger STI.
      expect(group.group_type).to eq("person")
      expect(group.actual).to be(true)
      expect(group.code_value).to eq("checkup-2026")
      expect(group.managing_entity_reference).to eq("Organization/o1")
    end

    it "is nil-safe when fields are absent" do
      group = build_group({})

      expect { group.sync_search_fields! }.not_to raise_error
      expect(group.group_type).to be_nil
      expect(group.actual).to be_nil
      expect(group.code_value).to be_nil
    end
  end

  describe "#sync_tokens!" do
    it "emits rows for type and every code coding" do
      group = build_group(
        "type" => "person",
        "code" => {
          "coding" => [
            { "system" => "http://example.org/CodeSystem/cohort", "code" => "checkup-2026" },
            { "system" => "http://example.org/local", "code" => "LOCAL-1" }
          ]
        }
      )

      group.save!(validate: false)
      group.sync_tokens!

      expect(group.resource_tokens.where(param_name: "type").pluck(:code)).to eq(["person"])
      expect(group.resource_tokens.where(param_name: "code").pluck(:system, :code))
        .to contain_exactly(
          ["http://example.org/CodeSystem/cohort", "checkup-2026"],
          ["http://example.org/local", "LOCAL-1"]
        )
    end
  end
end
