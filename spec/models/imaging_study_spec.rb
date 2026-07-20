require "rails_helper"

RSpec.describe ImagingStudy do
  def build_imaging_study(content)
    described_class.new(
      id: SecureRandom.uuid,
      version_id: 1,
      content: content,
      last_updated: Time.current
    )
  end

  describe "#sync_search_fields!" do
    it "extracts status, modality, subject, encounter, and started" do
      study = build_imaging_study(
        "status" => "available",
        "modality" => [{ "system" => "http://dicom.nema.org/resources/ontology/DCM", "code" => "CT" }],
        "subject" => { "reference" => "Patient/abc123" },
        "encounter" => { "reference" => "Encounter/enc1" },
        "started" => "2026-07-19T10:00:00+09:00"
      )

      study.sync_search_fields!

      expect(study.status).to eq("available")
      expect(study.modality_code).to eq("CT")
      expect(study.subject_reference).to eq("Patient/abc123")
      expect(study.encounter_reference).to eq("Encounter/enc1")
      expect(study.started).to eq(Time.iso8601("2026-07-19T10:00:00+09:00"))
    end

    it "is nil-safe when fields are absent" do
      study = build_imaging_study({})

      expect { study.sync_search_fields! }.not_to raise_error
      expect(study.started).to be_nil
      expect(study.modality_code).to be_nil
    end
  end
end
