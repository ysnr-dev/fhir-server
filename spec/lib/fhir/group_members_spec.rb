require "rails_helper"

RSpec.describe Fhir::GroupMembers do
  def create_patient
    Fhir::Repository.create(
      "Patient",
      { "resourceType" => "Patient", "identifier" => [{ "system" => "urn:example", "value" => SecureRandom.hex(4) }] }
    )
  end

  def build_group(members)
    Fhir::Repository.create(
      "Group",
      { "resourceType" => "Group", "type" => "person", "actual" => true, "member" => members }
    )
  end

  describe ".patient_ids" do
    it "resolves Patient members to their logical ids" do
      first = create_patient
      second = create_patient
      group = build_group([
                            { "entity" => { "reference" => "Patient/#{first.id}" } },
                            { "entity" => { "reference" => "Patient/#{second.id}" } }
                          ])

      expect(described_class.patient_ids(group)).to contain_exactly(first.id, second.id)
    end

    it "returns an empty list for a group with no members" do
      group = Fhir::Repository.create(
        "Group", { "resourceType" => "Group", "type" => "person", "actual" => false }
      )

      expect(described_class.patient_ids(group)).to eq([])
    end

    it "skips members flagged inactive" do
      active = create_patient
      inactive = create_patient
      group = build_group([
                            { "entity" => { "reference" => "Patient/#{active.id}" } },
                            { "entity" => { "reference" => "Patient/#{inactive.id}" }, "inactive" => true }
                          ])

      expect(described_class.patient_ids(group)).to eq([active.id])
    end

    it "skips non-Patient members" do
      patient = create_patient
      group = build_group([
                            { "entity" => { "reference" => "Patient/#{patient.id}" } },
                            { "entity" => { "reference" => "Practitioner/pr1" } },
                            { "entity" => { "reference" => "Device/d1" } }
                          ])

      expect(described_class.patient_ids(group)).to eq([patient.id])
    end

    # GroupValidator rejects a dangling member at write time, but a Patient can
    # be deleted after the group is created -- the cohort then simply shrinks.
    it "skips patients deleted after the group was written" do
      kept = create_patient
      removed = create_patient
      group = build_group([
                            { "entity" => { "reference" => "Patient/#{kept.id}" } },
                            { "entity" => { "reference" => "Patient/#{removed.id}" } }
                          ])
      Fhir::Repository.delete("Patient", removed)

      expect(described_class.patient_ids(group)).to eq([kept.id])
    end

    it "ignores members with no entity reference" do
      patient = create_patient
      group = build_group([
                            { "entity" => { "reference" => "Patient/#{patient.id}" } },
                            { "period" => { "start" => "2026-01-01" } }
                          ])

      expect(described_class.patient_ids(group)).to eq([patient.id])
    end

    it "de-duplicates a patient listed twice" do
      patient = create_patient
      group = build_group([
                            { "entity" => { "reference" => "Patient/#{patient.id}" } },
                            { "entity" => { "reference" => "Patient/#{patient.id}" } }
                          ])

      expect(described_class.patient_ids(group)).to eq([patient.id])
    end
  end
end
