require "rails_helper"

RSpec.describe MedicationRequestRepository do
  let(:patient) do
    PatientRepository.create(
      { "resourceType" => "Patient",
        "identifier" => [{ "system" => "urn:oid:1.2.392.100495.20.3.51", "value" => "P1" }] }
    )
  end

  def payload(overrides = {})
    {
      "resourceType" => "MedicationRequest",
      "identifier" => [{ "system" => "http://jpfhir.jp/fhir/core/mhlw/IdSystem/Medication-RPGroupNumber", "value" => "1" }],
      "status" => "active",
      "intent" => "order",
      "medicationCodeableConcept" => {
        "coding" => [{ "system" => "urn:oid:1.2.392.100495.20.2.74", "code" => "620004422", "display" => "Drug" }]
      },
      "subject" => { "reference" => "Patient/#{patient.id}" },
      "authoredOn" => "2026-07-19T10:00:00+09:00"
    }.deep_merge(overrides.deep_stringify_keys)
  end

  describe ".create" do
    it "assigns a server-generated id, version 1, and extracts search fields" do
      medication_request = described_class.create(payload)

      expect(medication_request.id).to be_present
      expect(medication_request.version_id).to eq(1)
      expect(medication_request.status).to eq("active")
      expect(medication_request.intent).to eq("order")
      expect(medication_request.subject_reference).to eq("Patient/#{patient.id}")
      expect(medication_request.medication_code).to eq("620004422")
    end

    it "creates matching medication_request_identifiers rows" do
      medication_request = described_class.create(payload)

      expect(medication_request.medication_request_identifiers.pluck(:value)).to eq(["1"])
    end

    it "writes an initial version row" do
      medication_request = described_class.create(payload)

      versions = described_class.history(medication_request.id)
      expect(versions.size).to eq(1)
    end

    it "strips any client-supplied id and meta" do
      medication_request = described_class.create(payload("id" => "client-supplied", "meta" => { "versionId" => "99" }))

      expect(medication_request.id).not_to eq("client-supplied")
      expect(medication_request.content).not_to have_key("meta")
    end
  end

  describe ".update" do
    it "increments the version and updates content" do
      medication_request = described_class.create(payload)

      updated = described_class.update(medication_request, payload("status" => "completed"))

      expect(updated.version_id).to eq(2)
      expect(updated.status).to eq("completed")
    end

    it "raises VersionConflict when if_match_version does not match" do
      medication_request = described_class.create(payload)

      expect do
        described_class.update(medication_request, payload, if_match_version: "99")
      end.to raise_error(described_class::VersionConflict)
    end
  end

  describe ".delete" do
    it "marks deleted and bumps the version" do
      medication_request = described_class.create(payload)

      described_class.delete(medication_request)

      expect(medication_request.reload.deleted).to eq(true)
      expect(medication_request.version_id).to eq(2)
    end

    it "is idempotent when called twice" do
      medication_request = described_class.create(payload)

      described_class.delete(medication_request)
      expect { described_class.delete(medication_request.reload) }.not_to change { medication_request.reload.version_id }
    end
  end

  describe ".version" do
    it "returns a specific historical version" do
      medication_request = described_class.create(payload)
      described_class.update(medication_request, payload("status" => "completed"))

      v1 = described_class.version(medication_request.id, 1)
      v2 = described_class.version(medication_request.id, 2)

      expect(v1.content["status"]).to eq("active")
      expect(v2.content["status"]).to eq("completed")
    end
  end
end
