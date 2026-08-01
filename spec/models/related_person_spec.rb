require "rails_helper"

RSpec.describe RelatedPerson do
  def build_related_person(content)
    described_class.new(
      id: SecureRandom.uuid,
      version_id: 1,
      content: content,
      last_updated: Time.current
    )
  end

  describe "#sync_search_fields!" do
    it "extracts active, patient, relationship, name, gender, and birthDate" do
      related_person = build_related_person(
        "active" => true,
        "patient" => { "reference" => "Patient/p1" },
        "relationship" => [
          { "coding" => [{ "system" => "http://terminology.hl7.org/CodeSystem/v3-RoleCode", "code" => "MTH" }] }
        ],
        "name" => [
          { "use" => "official", "family" => "山田", "given" => ["花子"] },
          { "use" => "usual", "text" => "ヤマダ ハナコ" }
        ],
        "gender" => "female",
        "birthDate" => "1970-04-01"
      )

      related_person.sync_search_fields!

      expect(related_person.active).to be(true)
      expect(related_person.patient_reference).to eq("Patient/p1")
      expect(related_person.relationship_code).to eq("MTH")
      # Kana representations land in name_text alongside the official name.
      expect(related_person.name_text).to eq("山田 花子 ヤマダ ハナコ")
      expect(related_person.gender).to eq("female")
      expect(related_person.birth_date).to eq(Date.new(1970, 4, 1))
    end

    it "stores a partial birthDate as the first day of its precision" do
      related_person = build_related_person("birthDate" => "1970")

      related_person.sync_search_fields!

      expect(related_person.birth_date).to eq(Date.new(1970, 1, 1))
    end

    it "is nil-safe when fields are absent" do
      related_person = build_related_person({})

      expect { related_person.sync_search_fields! }.not_to raise_error
      expect(related_person.patient_reference).to be_nil
      expect(related_person.relationship_code).to be_nil
      expect(related_person.birth_date).to be_nil
    end
  end

  describe "#sync_tokens!" do
    it "emits rows for gender and every relationship coding" do
      related_person = build_related_person(
        "gender" => "female",
        "relationship" => [
          { "coding" => [{ "system" => "http://terminology.hl7.org/CodeSystem/v3-RoleCode", "code" => "MTH" }] },
          { "coding" => [{ "system" => "http://example.org/local", "code" => "GUARDIAN" }] }
        ]
      )

      related_person.save!(validate: false)
      related_person.sync_tokens!

      expect(related_person.resource_tokens.where(param_name: "gender").pluck(:code)).to eq(["female"])
      expect(related_person.resource_tokens.where(param_name: "relationship").pluck(:system, :code))
        .to contain_exactly(
          ["http://terminology.hl7.org/CodeSystem/v3-RoleCode", "MTH"],
          ["http://example.org/local", "GUARDIAN"]
        )
    end
  end
end
