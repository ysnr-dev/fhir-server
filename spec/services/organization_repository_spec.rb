require "rails_helper"

RSpec.describe OrganizationRepository do
  def payload(overrides = {})
    {
      "resourceType" => "Organization",
      "identifier" => [{ "system" => "http://jpfhir.jp/fhir/core/IdSystem/insurance-medical-institution-no", "value" => "12345" }],
      "name" => "サンプル病院",
      "active" => true
    }.deep_merge(overrides.deep_stringify_keys)
  end

  describe ".create" do
    it "assigns a server-generated id and version 1" do
      organization = described_class.create(payload)

      expect(organization.id).to be_present
      expect(organization.version_id).to eq(1)
      expect(organization.name).to eq("サンプル病院")
    end

    it "creates a matching organization_identifiers row" do
      organization = described_class.create(payload)

      expect(organization.organization_identifiers.pluck(:value)).to eq(["12345"])
    end

    it "writes an initial version row" do
      organization = described_class.create(payload)

      expect(described_class.history(organization.id).size).to eq(1)
    end
  end

  describe ".update" do
    it "increments the version and updates content" do
      organization = described_class.create(payload)

      updated = described_class.update(organization, payload("name" => "別の病院"))

      expect(updated.version_id).to eq(2)
      expect(updated.name).to eq("別の病院")
    end

    it "raises VersionConflict when if_match_version does not match" do
      organization = described_class.create(payload)

      expect do
        described_class.update(organization, payload, if_match_version: "99")
      end.to raise_error(described_class::VersionConflict)
    end
  end

  describe ".delete" do
    it "marks the organization deleted and bumps the version" do
      organization = described_class.create(payload)

      described_class.delete(organization)

      expect(organization.reload.deleted).to eq(true)
      expect(organization.version_id).to eq(2)
    end
  end
end
