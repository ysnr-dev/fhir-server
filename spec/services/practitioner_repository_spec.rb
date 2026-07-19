require "rails_helper"

RSpec.describe PractitionerRepository do
  def payload(overrides = {})
    {
      "resourceType" => "Practitioner",
      "identifier" => [{ "system" => "http://jpfhir.jp/fhir/core/mhlw/IdSystem/medicalRegistrationNumber", "value" => "12345" }],
      "name" => [{ "use" => "official", "family" => "鈴木", "given" => ["一郎"] }],
      "gender" => "male",
      "birthDate" => "1980-01-01"
    }.deep_merge(overrides.deep_stringify_keys)
  end

  describe ".create" do
    it "assigns a server-generated id and version 1" do
      practitioner = described_class.create(payload)

      expect(practitioner.id).to be_present
      expect(practitioner.version_id).to eq(1)
      expect(practitioner.content["resourceType"]).to eq("Practitioner")
    end

    it "succeeds with an entirely empty resource (no required fields)" do
      practitioner = described_class.create({ "resourceType" => "Practitioner" })

      expect(practitioner.id).to be_present
      expect(practitioner.version_id).to eq(1)
    end

    it "creates a matching practitioner_identifiers row" do
      practitioner = described_class.create(payload)

      expect(practitioner.practitioner_identifiers.pluck(:value)).to eq(["12345"])
    end

    it "writes an initial version row" do
      practitioner = described_class.create(payload)

      expect(described_class.history(practitioner.id).size).to eq(1)
    end
  end

  describe ".update" do
    it "increments the version and updates content" do
      practitioner = described_class.create(payload)

      updated = described_class.update(practitioner, payload("gender" => "female"))

      expect(updated.version_id).to eq(2)
      expect(updated.content["gender"]).to eq("female")
    end

    it "raises VersionConflict when if_match_version does not match" do
      practitioner = described_class.create(payload)

      expect do
        described_class.update(practitioner, payload, if_match_version: "99")
      end.to raise_error(described_class::VersionConflict)
    end
  end

  describe ".delete" do
    it "marks the practitioner deleted and bumps the version" do
      practitioner = described_class.create(payload)

      described_class.delete(practitioner)

      expect(practitioner.reload.deleted).to eq(true)
      expect(practitioner.version_id).to eq(2)
    end
  end
end
