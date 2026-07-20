require "rails_helper"

RSpec.describe PractitionerRole do
  def build_practitioner_role(content)
    described_class.new(
      id: SecureRandom.uuid,
      version_id: 1,
      content: content,
      last_updated: Time.current
    )
  end

  describe "#sync_search_fields!" do
    it "extracts active, references, and the first role/specialty codes" do
      practitioner_role = build_practitioner_role(
        "active" => true,
        "practitioner" => { "reference" => "Practitioner/p1" },
        "organization" => { "reference" => "Organization/o1" },
        "code" => [{ "coding" => [{ "code" => "doctor" }] }],
        "specialty" => [{ "coding" => [{ "code" => "394814009" }] }]
      )

      practitioner_role.sync_search_fields!

      expect(practitioner_role.active).to eq(true)
      expect(practitioner_role.practitioner_reference).to eq("Practitioner/p1")
      expect(practitioner_role.organization_reference).to eq("Organization/o1")
      expect(practitioner_role.role_code).to eq("doctor")
      expect(practitioner_role.specialty_code).to eq("394814009")
    end

    it "is nil-safe when fields are absent" do
      practitioner_role = build_practitioner_role({})

      expect { practitioner_role.sync_search_fields! }.not_to raise_error
      expect(practitioner_role.practitioner_reference).to be_nil
      expect(practitioner_role.role_code).to be_nil
    end
  end
end
