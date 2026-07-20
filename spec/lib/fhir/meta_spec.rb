require "rails_helper"

RSpec.describe Fhir::Meta do
  describe ".apply" do
    it "injects versionId and lastUpdated" do
      resource = { "resourceType" => "Patient", "id" => "p1" }
      last_updated = Time.utc(2026, 7, 19, 12, 0, 0)

      result = described_class.apply(resource, version_id: 3, last_updated: last_updated)

      expect(result["meta"]["versionId"]).to eq("3")
      expect(result["meta"]["lastUpdated"]).to eq("2026-07-19T12:00:00.000Z")
    end

    it "sets meta.profile from the registered resource type's profile" do
      resource = { "resourceType" => "Patient", "id" => "p1" }

      result = described_class.apply(resource, version_id: 1, last_updated: Time.current)

      expect(result["meta"]["profile"]).to eq(["http://jpfhir.jp/fhir/core/StructureDefinition/JP_Patient"])
    end

    it "resolves the profile from the resource's own resourceType, not a fixed type" do
      resource = { "resourceType" => "Encounter", "id" => "e1" }

      result = described_class.apply(resource, version_id: 1, last_updated: Time.current)

      expect(result["meta"]["profile"]).to eq(["http://jpfhir.jp/fhir/core/StructureDefinition/JP_Encounter"])
    end

    it "omits meta.profile for a resourceType with no registry entry" do
      resource = { "resourceType" => "Bundle", "id" => "b1" }

      result = described_class.apply(resource, version_id: 1, last_updated: Time.current)

      expect(result["meta"]).not_to have_key("profile")
    end

    it "overwrites client-supplied meta.versionId/lastUpdated/profile while leaving other meta keys alone" do
      resource = {
        "resourceType" => "Patient", "id" => "p1",
        "meta" => { "versionId" => "999", "lastUpdated" => "2000-01-01T00:00:00Z",
                    "profile" => ["http://example.org/bogus"], "security" => [{ "code" => "R" }] }
      }

      result = described_class.apply(resource, version_id: 2, last_updated: Time.utc(2026, 1, 1))

      expect(result["meta"]["versionId"]).to eq("2")
      expect(result["meta"]["profile"]).to eq(["http://jpfhir.jp/fhir/core/StructureDefinition/JP_Patient"])
      expect(result["meta"]["security"]).to eq([{ "code" => "R" }])
    end

    it "does not mutate the input resource" do
      resource = { "resourceType" => "Patient", "id" => "p1" }

      described_class.apply(resource, version_id: 1, last_updated: Time.current)

      expect(resource["meta"]).to be_nil
    end
  end
end
