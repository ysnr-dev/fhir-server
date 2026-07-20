require "rails_helper"

RSpec.describe Location do
  def build_location(content)
    described_class.new(
      id: SecureRandom.uuid,
      version_id: 1,
      content: content,
      last_updated: Time.current
    )
  end

  describe "#sync_search_fields!" do
    it "extracts status, name, managing organization, and the first type code" do
      location = build_location(
        "status" => "active",
        "name" => "第1診察室",
        "type" => [{ "coding" => [{ "code" => "HOSP" }] }],
        "managingOrganization" => { "reference" => "Organization/o1" }
      )

      location.sync_search_fields!

      expect(location.status).to eq("active")
      expect(location.name).to eq("第1診察室")
      expect(location.type_code).to eq("HOSP")
      expect(location.organization_reference).to eq("Organization/o1")
    end

    it "flattens the address into address_text" do
      location = build_location(
        "address" => { "text" => "東京都千代田区1-1-1", "city" => "千代田区", "postalCode" => "100-0001" }
      )

      location.sync_search_fields!

      expect(location.address_text).to include("東京都千代田区1-1-1", "千代田区", "100-0001")
    end

    it "is nil-safe when fields are absent" do
      location = build_location({})

      expect { location.sync_search_fields! }.not_to raise_error
      expect(location.address_text).to be_nil
      expect(location.type_code).to be_nil
    end
  end
end
