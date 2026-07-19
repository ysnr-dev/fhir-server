require "rails_helper"

RSpec.describe ServiceRequestRepository do
  let(:patient) do
    PatientRepository.create(
      { "resourceType" => "Patient",
        "identifier" => [{ "system" => "urn:oid:1.2.392.100495.20.3.51", "value" => "P1" }] }
    )
  end

  def payload(overrides = {})
    {
      "resourceType" => "ServiceRequest",
      "identifier" => [{ "system" => "http://example.org/sr", "value" => "1" }],
      "status" => "active",
      "intent" => "order",
      "code" => { "coding" => [{ "system" => "http://snomed.info/sct", "code" => "396550006", "display" => "Drug" }] },
      "subject" => { "reference" => "Patient/#{patient.id}" },
      "authoredOn" => "2026-07-19T10:00:00+09:00"
    }.deep_merge(overrides.deep_stringify_keys)
  end

  describe ".create" do
    it "assigns a server-generated id, version 1, and extracts search fields" do
      service_request = described_class.create(payload)

      expect(service_request.id).to be_present
      expect(service_request.version_id).to eq(1)
      expect(service_request.status).to eq("active")
      expect(service_request.intent).to eq("order")
      expect(service_request.subject_reference).to eq("Patient/#{patient.id}")
      expect(service_request.code).to eq("396550006")
    end

    it "accepts a pre-assigned id (used by Bundle transaction processing)" do
      pre_assigned = SecureRandom.uuid

      service_request = described_class.create(payload, id: pre_assigned)

      expect(service_request.id).to eq(pre_assigned)
    end

    it "creates matching service_request_identifiers rows" do
      service_request = described_class.create(payload)

      expect(service_request.service_request_identifiers.pluck(:value)).to eq(["1"])
    end

    it "writes an initial version row" do
      service_request = described_class.create(payload)

      versions = described_class.history(service_request.id)
      expect(versions.size).to eq(1)
    end
  end

  describe ".update" do
    it "increments the version and updates content" do
      service_request = described_class.create(payload)

      updated = described_class.update(service_request, payload("status" => "completed"))

      expect(updated.version_id).to eq(2)
      expect(updated.status).to eq("completed")
    end

    it "raises VersionConflict when if_match_version does not match" do
      service_request = described_class.create(payload)

      expect do
        described_class.update(service_request, payload, if_match_version: "99")
      end.to raise_error(described_class::VersionConflict)
    end
  end

  describe ".delete" do
    it "marks deleted and bumps the version" do
      service_request = described_class.create(payload)

      described_class.delete(service_request)

      expect(service_request.reload.deleted).to eq(true)
      expect(service_request.version_id).to eq(2)
    end
  end

  describe ".version" do
    it "returns a specific historical version" do
      service_request = described_class.create(payload)
      described_class.update(service_request, payload("status" => "completed"))

      v1 = described_class.version(service_request.id, 1)
      v2 = described_class.version(service_request.id, 2)

      expect(v1.content["status"]).to eq("active")
      expect(v2.content["status"]).to eq("completed")
    end
  end
end
