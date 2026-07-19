require "rails_helper"

RSpec.describe PatientRepository do
  def payload(overrides = {})
    {
      "resourceType" => "Patient",
      "identifier" => [{ "system" => "urn:oid:1.2.392.100495.20.3.51", "value" => "12345" }],
      "gender" => "male",
      "birthDate" => "1990-01-01"
    }.deep_merge(overrides.deep_stringify_keys)
  end

  describe ".create" do
    it "assigns a server-generated id and version 1" do
      patient = described_class.create(payload)

      expect(patient.id).to be_present
      expect(patient.version_id).to eq(1)
      expect(patient.content["resourceType"]).to eq("Patient")
      expect(patient.content["id"]).to eq(patient.id)
    end

    it "creates a matching patient_identifiers row" do
      patient = described_class.create(payload)

      expect(patient.patient_identifiers.pluck(:value)).to eq(["12345"])
    end

    it "writes an initial patient_versions row" do
      patient = described_class.create(payload)

      versions = described_class.history(patient.id)
      expect(versions.size).to eq(1)
      expect(versions.first.version_id).to eq(1)
    end

    it "strips any client-supplied id and meta" do
      patient = described_class.create(payload("id" => "client-supplied", "meta" => { "versionId" => "99" }))

      expect(patient.id).not_to eq("client-supplied")
      expect(patient.content).not_to have_key("meta")
    end
  end

  describe ".update" do
    it "increments the version and updates content" do
      patient = described_class.create(payload)

      updated = described_class.update(patient, payload(gender: "female"))

      expect(updated.version_id).to eq(2)
      expect(updated.content["gender"]).to eq("female")
    end

    it "raises VersionConflict when if_match_version does not match" do
      patient = described_class.create(payload)

      expect do
        described_class.update(patient, payload, if_match_version: "99")
      end.to raise_error(described_class::VersionConflict)
    end

    it "succeeds when if_match_version matches" do
      patient = described_class.create(payload)

      expect { described_class.update(patient, payload(gender: "female"), if_match_version: "1") }
        .not_to raise_error
    end

    it "rebuilds patient_identifiers on update" do
      patient = described_class.create(payload)

      described_class.update(patient, payload("identifier" => [{ "system" => "urn:oid:1.2.392.100495.20.3.51", "value" => "99999" }]))

      expect(patient.reload.patient_identifiers.pluck(:value)).to eq(["99999"])
    end
  end

  describe ".delete" do
    it "marks the patient deleted and bumps the version" do
      patient = described_class.create(payload)

      described_class.delete(patient)

      expect(patient.reload.deleted).to eq(true)
      expect(patient.version_id).to eq(2)
    end

    it "is idempotent when called twice" do
      patient = described_class.create(payload)

      described_class.delete(patient)
      expect { described_class.delete(patient.reload) }.not_to change { patient.reload.version_id }
    end

    it "records a deleted version in history" do
      patient = described_class.create(payload)

      described_class.delete(patient)

      versions = described_class.history(patient.id)
      expect(versions.last.deleted).to eq(true)
    end
  end

  describe ".version" do
    it "returns a specific historical version" do
      patient = described_class.create(payload)
      described_class.update(patient, payload(gender: "female"))

      v1 = described_class.version(patient.id, 1)
      v2 = described_class.version(patient.id, 2)

      expect(v1.content["gender"]).to eq("male")
      expect(v2.content["gender"]).to eq("female")
    end
  end
end
