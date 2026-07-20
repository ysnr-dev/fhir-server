require "rails_helper"

RSpec.describe Fhir::Repository do
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
      patient = described_class.create("Patient", payload)

      expect(patient.id).to be_present
      expect(patient.version_id).to eq(1)
      expect(patient.content["resourceType"]).to eq("Patient")
      expect(patient.content["id"]).to eq(patient.id)
    end

    it "creates a matching resource_identifiers row" do
      patient = described_class.create("Patient", payload)

      expect(patient.resource_identifiers.pluck(:value)).to eq(["12345"])
      expect(ResourceIdentifier.where(resource_type: "Patient", resource_id: patient.id).pluck(:value)).to eq(["12345"])
    end

    it "writes an initial resource_versions row" do
      patient = described_class.create("Patient", payload)

      versions = described_class.history("Patient", patient.id)
      expect(versions.size).to eq(1)
      expect(versions.first.version_id).to eq(1)
      expect(versions.first.resource_type).to eq("Patient")
    end

    it "strips any client-supplied id and meta" do
      patient = described_class.create("Patient", payload("id" => "client-supplied", "meta" => { "versionId" => "99" }))

      expect(patient.id).not_to eq("client-supplied")
      expect(patient.content).not_to have_key("meta")
    end
  end

  describe ".update" do
    it "increments the version and updates content" do
      patient = described_class.create("Patient", payload)

      updated = described_class.update("Patient", patient, payload(gender: "female"))

      expect(updated.version_id).to eq(2)
      expect(updated.content["gender"]).to eq("female")
    end

    it "raises VersionConflict when if_match_version does not match" do
      patient = described_class.create("Patient", payload)

      expect do
        described_class.update("Patient", patient, payload, if_match_version: "99")
      end.to raise_error(described_class::VersionConflict)
    end

    it "succeeds when if_match_version matches" do
      patient = described_class.create("Patient", payload)

      expect { described_class.update("Patient", patient, payload(gender: "female"), if_match_version: "1") }
        .not_to raise_error
    end

    it "rebuilds resource_identifiers on update" do
      patient = described_class.create("Patient", payload)

      described_class.update(
        "Patient", patient,
        payload("identifier" => [{ "system" => "urn:oid:1.2.392.100495.20.3.51", "value" => "99999" }])
      )

      expect(patient.reload.resource_identifiers.pluck(:value)).to eq(["99999"])
    end
  end

  describe ".delete" do
    it "marks the record deleted and bumps the version" do
      patient = described_class.create("Patient", payload)

      described_class.delete("Patient", patient)

      expect(patient.reload.deleted).to eq(true)
      expect(patient.version_id).to eq(2)
    end

    it "is idempotent when called twice" do
      patient = described_class.create("Patient", payload)

      described_class.delete("Patient", patient)
      expect { described_class.delete("Patient", patient.reload) }.not_to change { patient.reload.version_id }
    end

    it "records a deleted version in history" do
      patient = described_class.create("Patient", payload)

      described_class.delete("Patient", patient)

      versions = described_class.history("Patient", patient.id)
      expect(versions.last.deleted).to eq(true)
    end
  end

  describe ".version" do
    it "returns a specific historical version" do
      patient = described_class.create("Patient", payload)
      described_class.update("Patient", patient, payload(gender: "female"))

      v1 = described_class.version("Patient", patient.id, 1)
      v2 = described_class.version("Patient", patient.id, 2)

      expect(v1.content["gender"]).to eq("male")
      expect(v2.content["gender"]).to eq("female")
    end
  end

  describe "every registered resource type" do
    def minimal_payload(resource_type, patient_id:, organization_id: nil)
      case resource_type
      when "Patient"
        { "resourceType" => "Patient",
          "identifier" => [{ "system" => "urn:oid:1.2.392.100495.20.3.51", "value" => "smoke-patient" }] }
      when "Practitioner"
        { "resourceType" => "Practitioner",
          "identifier" => [{ "system" => "http://jpfhir.jp/fhir/core/mhlw/IdSystem/medicalRegistrationNumber",
                              "value" => "smoke-practitioner" }],
          "name" => [{ "use" => "official", "family" => "Smoke", "given" => ["Test"] }] }
      when "Organization"
        { "resourceType" => "Organization",
          "identifier" => [{ "system" => "http://jpfhir.jp/fhir/core/IdSystem/insurance-medical-institution-no",
                              "value" => "smoke-org" }],
          "name" => "Smoke Test Hospital" }
      when "MedicationRequest"
        { "resourceType" => "MedicationRequest",
          "identifier" => [{ "system" => "http://jpfhir.jp/fhir/core/mhlw/IdSystem/Medication-RPGroupNumber",
                              "value" => "smoke-mr" }],
          "status" => "active",
          "intent" => "order",
          "medicationCodeableConcept" => {
            "coding" => [{ "system" => "urn:oid:1.2.392.100495.20.2.74", "code" => "620004422", "display" => "Drug" }]
          },
          "subject" => { "reference" => "Patient/#{patient_id}" } }
      when "Medication"
        { "resourceType" => "Medication",
          "identifier" => [{ "system" => "http://example.org/medication", "value" => "smoke-med" }],
          "status" => "active",
          "code" => { "coding" => [{ "system" => "urn:oid:1.2.392.100495.20.2.74", "code" => "620004422", "display" => "Drug" }] } }
      when "MedicationDispense"
        { "resourceType" => "MedicationDispense",
          "identifier" => [{ "system" => "http://example.org/medication-dispense", "value" => "smoke-md" }],
          "status" => "completed",
          "medicationCodeableConcept" => {
            "coding" => [{ "system" => "urn:oid:1.2.392.100495.20.2.74", "code" => "620004422", "display" => "Drug" }]
          },
          "subject" => { "reference" => "Patient/#{patient_id}" } }
      when "MedicationAdministration"
        { "resourceType" => "MedicationAdministration",
          "identifier" => [{ "system" => "http://example.org/medication-administration", "value" => "smoke-ma" }],
          "status" => "completed",
          "medicationCodeableConcept" => {
            "coding" => [{ "system" => "urn:oid:1.2.392.100495.20.2.74", "code" => "620004422", "display" => "Drug" }]
          },
          "subject" => { "reference" => "Patient/#{patient_id}" } }
      when "MedicationStatement"
        { "resourceType" => "MedicationStatement",
          "identifier" => [{ "system" => "http://example.org/medication-statement", "value" => "smoke-ms" }],
          "status" => "active",
          "medicationCodeableConcept" => {
            "coding" => [{ "system" => "urn:oid:1.2.392.100495.20.2.74", "code" => "620004422", "display" => "Drug" }]
          },
          "subject" => { "reference" => "Patient/#{patient_id}" } }
      when "Observation"
        { "resourceType" => "Observation",
          "identifier" => [{ "system" => "http://example.org/observation", "value" => "smoke-obs" }],
          "status" => "final",
          "code" => { "coding" => [{ "system" => "http://loinc.org", "code" => "718-7", "display" => "Hemoglobin" }] },
          "subject" => { "reference" => "Patient/#{patient_id}" } }
      when "Specimen"
        { "resourceType" => "Specimen",
          "identifier" => [{ "system" => "http://example.org/specimen", "value" => "smoke-spec" }],
          "status" => "available",
          "type" => { "coding" => [{ "system" => "http://terminology.hl7.org/CodeSystem/v2-0487", "code" => "BLD" }] },
          "subject" => { "reference" => "Patient/#{patient_id}" } }
      when "ImagingStudy"
        { "resourceType" => "ImagingStudy",
          "identifier" => [{ "system" => "urn:dicom:uid", "value" => "smoke-imaging" }],
          "status" => "available",
          "modality" => [{ "system" => "http://dicom.nema.org/resources/ontology/DCM", "code" => "CT" }],
          "subject" => { "reference" => "Patient/#{patient_id}" } }
      when "DiagnosticReport"
        { "resourceType" => "DiagnosticReport",
          "identifier" => [{ "system" => "http://example.org/diagnostic-report", "value" => "smoke-dr" }],
          "status" => "final",
          "code" => { "coding" => [{ "system" => "http://loinc.org", "code" => "58410-2", "display" => "CBC panel" }] },
          "subject" => { "reference" => "Patient/#{patient_id}" } }
      when "ServiceRequest"
        { "resourceType" => "ServiceRequest",
          "identifier" => [{ "system" => "http://example.org/sr", "value" => "smoke-sr" }],
          "status" => "active",
          "intent" => "order",
          "code" => { "coding" => [{ "system" => "http://snomed.info/sct", "code" => "396550006", "display" => "Drug" }] },
          "subject" => { "reference" => "Patient/#{patient_id}" } }
      when "PractitionerRole"
        { "resourceType" => "PractitionerRole",
          "identifier" => [{ "system" => "http://example.org/practitioner-role", "value" => "smoke-pr" }],
          "active" => true,
          "practitioner" => { "reference" => "Practitioner/#{patient_id}" } }
      when "Encounter"
        { "resourceType" => "Encounter",
          "identifier" => [{ "system" => "http://example.org/encounter", "value" => "smoke-enc" }],
          "status" => "finished",
          "class" => { "system" => "http://terminology.hl7.org/CodeSystem/v3-ActCode", "code" => "AMB" },
          "subject" => { "reference" => "Patient/#{patient_id}" } }
      when "Location"
        { "resourceType" => "Location",
          "identifier" => [{ "system" => "http://example.org/location", "value" => "smoke-loc" }],
          "status" => "active",
          "name" => "Smoke Room" }
      when "Condition"
        { "resourceType" => "Condition",
          "identifier" => [{ "system" => "http://example.org/condition", "value" => "smoke-cond" }],
          "code" => { "coding" => [{ "system" => "http://hl7.org/fhir/sid/icd-10", "code" => "J20.9" }] },
          "subject" => { "reference" => "Patient/#{patient_id}" } }
      when "AllergyIntolerance"
        { "resourceType" => "AllergyIntolerance",
          "identifier" => [{ "system" => "http://example.org/allergy", "value" => "smoke-allergy" }],
          "code" => { "coding" => [{ "system" => "http://www.nlm.nih.gov/research/umls/rxnorm", "code" => "7980" }] },
          "patient" => { "reference" => "Patient/#{patient_id}" } }
      when "Procedure"
        { "resourceType" => "Procedure",
          "identifier" => [{ "system" => "http://example.org/procedure", "value" => "smoke-proc" }],
          "status" => "completed",
          "code" => { "coding" => [{ "system" => "http://snomed.info/sct", "code" => "80146002" }] },
          "subject" => { "reference" => "Patient/#{patient_id}" } }
      when "Immunization"
        { "resourceType" => "Immunization",
          "identifier" => [{ "system" => "http://example.org/immunization", "value" => "smoke-imm" }],
          "status" => "completed",
          "vaccineCode" => { "coding" => [{ "system" => "http://hl7.org/fhir/sid/ndc", "code" => "49281-0215-88" }] },
          "patient" => { "reference" => "Patient/#{patient_id}" },
          "occurrenceDateTime" => "2026-07-19T10:00:00+09:00" }
      when "Coverage"
        { "resourceType" => "Coverage",
          "identifier" => [{ "system" => "http://example.org/coverage", "value" => "smoke-cov" }],
          "status" => "active",
          "beneficiary" => { "reference" => "Patient/#{patient_id}" },
          "payor" => [{ "reference" => "Organization/#{organization_id}" }] }
      else
        raise "No smoke-test fixture defined for #{resource_type} -- add one when registering the type"
      end
    end

    let(:patient_id) { described_class.create("Patient", minimal_payload("Patient", patient_id: nil)).id }
    let(:organization_id) { described_class.create("Organization", minimal_payload("Organization", patient_id: nil)).id }

    Fhir::ResourceRegistry.types.each do |resource_type|
      it "round-trips create -> update -> history and extracts identifiers for #{resource_type}" do
        fixture = minimal_payload(resource_type, patient_id: patient_id, organization_id: organization_id)

        record = described_class.create(resource_type, fixture)
        expect(record.version_id).to eq(1)
        expect(record.resource_identifiers.pluck(:value)).not_to be_empty

        updated = described_class.update(resource_type, record, fixture)
        expect(updated.version_id).to eq(2)

        versions = described_class.history(resource_type, record.id)
        expect(versions.map(&:version_id)).to eq([1, 2])
      end
    end
  end
end
