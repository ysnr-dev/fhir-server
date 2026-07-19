require "rails_helper"

RSpec.describe Organization do
  def build_organization(content)
    described_class.new(
      id: SecureRandom.uuid,
      version_id: 1,
      content: content,
      last_updated: Time.current
    )
  end

  describe "#sync_search_fields!" do
    it "extracts active and name" do
      organization = build_organization("active" => true, "name" => "サンプル病院")

      organization.sync_search_fields!

      expect(organization.active).to eq(true)
      expect(organization.name).to eq("サンプル病院")
    end

    it "is nil-safe when fields are absent" do
      organization = build_organization({})

      expect { organization.sync_search_fields! }.not_to raise_error
      expect(organization.name).to be_nil
      expect(organization.active).to be_nil
    end
  end
end
