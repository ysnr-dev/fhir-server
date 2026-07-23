require "rails_helper"

RSpec.describe BulkExportGenerator do
  def create_patient(overrides = {})
    Fhir::Repository.create(
      "Patient",
      { "resourceType" => "Patient", "identifier" => [{ "system" => "urn:example", "value" => SecureRandom.hex(4) }] }
        .deep_merge(overrides.deep_stringify_keys)
    )
  end

  def create_observation(patient, overrides = {})
    Fhir::Repository.create(
      "Observation",
      {
        "resourceType" => "Observation",
        "status" => "final",
        "code" => { "coding" => [{ "system" => "http://loinc.org", "code" => "8867-4" }] },
        "subject" => { "reference" => "Patient/#{patient.id}" }
      }.deep_merge(overrides.deep_stringify_keys)
    )
  end

  def create_organization
    Fhir::Repository.create("Organization", { "resourceType" => "Organization", "name" => "Spec Org" })
  end

  def build_export(kind:, types: nil, since: nil)
    BulkExport.create!(
      id: SecureRandom.uuid, kind: kind, status: "in_progress", types: types, since: since,
      output_format: "application/fhir+ndjson", transaction_time: Time.current,
      request_url: "http://example.test/$export"
    )
  end

  def lines_for(export, type)
    export.bulk_export_files.where(resource_type: type).order(:sequence).flat_map { |f| f.content.split("\n") }
  end

  describe "system-level export" do
    it "writes one file per requested type with the current resource content" do
      patient = create_patient
      create_observation(patient)

      export = build_export(kind: "system", types: %w[Patient Observation])
      described_class.call(export)

      patient_lines = lines_for(export, "Patient").map { |l| JSON.parse(l) }
      observation_lines = lines_for(export, "Observation").map { |l| JSON.parse(l) }
      expect(patient_lines.map { |r| r["id"] }).to eq([patient.id])
      expect(observation_lines.size).to eq(1)
      expect(patient_lines.first.dig("meta", "versionId")).to eq(patient.version_id.to_s)
    end

    it "omits deleted resources and resources newer than the snapshot's transactionTime" do
      old = create_patient
      Fhir::Repository.delete("Patient", old)
      keep = create_patient
      too_new = create_patient
      Patient.where(id: too_new.id).update_all(last_updated: 1.hour.from_now)

      export = build_export(kind: "system", types: %w[Patient])
      export.update!(transaction_time: Time.current)

      described_class.call(export)

      ids = lines_for(export, "Patient").map { |l| JSON.parse(l)["id"] }
      expect(ids).to contain_exactly(keep.id)
      expect(ids).not_to include(old.id, too_new.id)
    end

    it "honors _since" do
      before = create_patient
      Patient.where(id: before.id).update_all(last_updated: 1.day.ago)
      after = create_patient

      export = build_export(kind: "system", types: %w[Patient], since: 1.hour.ago)
      described_class.call(export)

      ids = lines_for(export, "Patient").map { |l| JSON.parse(l)["id"] }
      expect(ids).to eq([after.id])
    end

    it "creates no file for a type with zero matching records" do
      export = build_export(kind: "system", types: %w[Patient])
      described_class.call(export)

      expect(export.bulk_export_files).to be_empty
    end

    it "splits a type across multiple files once the per-file byte cap is exceeded" do
      3.times { create_patient }
      stub_const("BulkExportGenerator::MAX_FILE_BYTES", 1) # force a flush after every record

      export = build_export(kind: "system", types: %w[Patient])
      described_class.call(export)

      files = export.bulk_export_files.where(resource_type: "Patient").order(:sequence)
      expect(files.count).to eq(3)
      expect(files.pluck(:sequence)).to eq([1, 2, 3])
    end

    it "fails with TooLarge once the total export exceeds the byte cap" do
      3.times { create_patient }
      stub_const("BulkExportGenerator::MAX_FILE_BYTES", 1)
      stub_const("BulkExportGenerator::MAX_TOTAL_BYTES", 1)

      export = build_export(kind: "system", types: %w[Patient])

      expect { described_class.call(export) }.to raise_error(BulkExportGenerator::TooLarge)
    end
  end

  describe "patient-level export" do
    it "always includes Patient resources and scopes other types to any patient's compartment" do
      patient = create_patient
      create_observation(patient)
      create_organization # no Patient-reference column -- must not appear

      export = build_export(kind: "patient", types: %w[Observation])
      described_class.call(export)

      expect(export.bulk_export_files.pluck(:resource_type)).to contain_exactly("Patient", "Observation")
    end
  end

  describe "cancellation" do
    it "stops generating further types once the export is cancelled" do
      create_patient
      create_observation(create_patient)

      export = build_export(kind: "system", types: %w[Patient Observation])
      export.update!(status: "cancelled")

      described_class.call(export)

      expect(export.bulk_export_files).to be_empty
    end
  end
end
