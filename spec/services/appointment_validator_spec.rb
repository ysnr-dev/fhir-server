require "rails_helper"

RSpec.describe AppointmentValidator do
  let(:patient) do
    Fhir::Repository.create(
      "Patient",
      { "resourceType" => "Patient",
        "identifier" => [{ "system" => "urn:oid:1.2.392.100495.20.3.51", "value" => "P1" }] }
    )
  end

  def payload(overrides = {})
    {
      "resourceType" => "Appointment",
      "status" => "booked",
      "start" => "2026-09-01T09:00:00+09:00",
      "end" => "2026-09-01T09:30:00+09:00",
      "participant" => [
        { "actor" => { "reference" => "Patient/#{patient.id}" }, "required" => "required", "status" => "accepted" },
        { "actor" => { "reference" => "Practitioner/pr1" }, "required" => "required", "status" => "accepted" }
      ]
    }.deep_merge(overrides.deep_stringify_keys)
  end

  it "is valid for a well-formed appointment" do
    result = described_class.call(payload)

    expect(result).to be_valid
    expect(result.warnings).to be_empty
  end

  describe "status" do
    it "rejects a missing status" do
      result = described_class.call(payload.except("status"))

      expect(result).not_to be_valid
      expect(result.errors.first[:code]).to eq("required")
    end

    it "rejects a status outside the appointmentstatus ValueSet" do
      # "free" is a Slot status, not an Appointment one.
      result = described_class.call(payload("status" => "free"))

      expect(result).not_to be_valid
      expect(result.errors.first[:code]).to eq("value")
    end
  end

  describe "start / end (app-2, app-3)" do
    it "rejects start without end" do
      result = described_class.call(payload.except("end"))

      expect(result).not_to be_valid
      expect(result.errors.first[:diagnostics]).to include("app-2")
    end

    it "rejects a booked appointment with neither start nor end (app-3)" do
      result = described_class.call(payload.except("start", "end"))

      expect(result).not_to be_valid
      expect(result.errors.first[:diagnostics]).to include("app-3")
    end

    it "accepts a proposed appointment with neither start nor end" do
      result = described_class.call(payload.except("start", "end").merge("status" => "proposed"))

      expect(result).to be_valid
    end

    it "accepts a waitlisted appointment with neither start nor end" do
      result = described_class.call(payload.except("start", "end").merge("status" => "waitlist"))

      expect(result).to be_valid
    end

    it "rejects an end at or before the start" do
      result = described_class.call(payload("end" => "2026-09-01T09:00:00+09:00"))

      expect(result).not_to be_valid
      expect(result.errors.first[:code]).to eq("invariant")
    end

    # start/end are `instant`, so a missing timezone would silently shift the
    # booking by the server's UTC offset.
    it "rejects an instant with no timezone offset" do
      result = described_class.call(payload("start" => "2026-09-01T09:00:00"))

      expect(result).not_to be_valid
      expect(result.errors.first[:diagnostics]).to include("instant")
    end
  end

  describe "cancelationReason (app-4)" do
    let(:reason) do
      { "coding" => [{ "system" => "http://terminology.hl7.org/CodeSystem/appointment-cancellation-reason",
                       "code" => "pat" }] }
    end

    it "rejects a cancelation reason on a booked appointment" do
      result = described_class.call(payload("cancelationReason" => reason))

      expect(result).not_to be_valid
      expect(result.errors.first[:diagnostics]).to include("app-4")
    end

    it "accepts a cancelation reason on a cancelled appointment" do
      result = described_class.call(payload("status" => "cancelled", "cancelationReason" => reason))

      expect(result).to be_valid
    end

    it "accepts a cancelation reason on a noshow appointment" do
      result = described_class.call(payload("status" => "noshow", "cancelationReason" => reason))

      expect(result).to be_valid
    end
  end

  describe "participant" do
    it "rejects an appointment with no participant" do
      result = described_class.call(payload.except("participant"))

      expect(result).not_to be_valid
      expect(result.errors.first[:diagnostics]).to include("1..*")
    end

    it "rejects a non-array participant, which `actor` search could not match" do
      result = described_class.call(payload.merge("participant" => { "status" => "accepted" }))

      expect(result).not_to be_valid
      expect(result.errors.first[:code]).to eq("structure")
    end

    # app-1: a participant with neither type nor actor names nobody.
    it "rejects a participant with neither type nor actor" do
      result = described_class.call(payload.merge("participant" => [{ "status" => "accepted" }]))

      expect(result).not_to be_valid
      expect(result.errors.map { |e| e[:diagnostics] }.join).to include("app-1")
    end

    it "accepts a type-only participant" do
      result = described_class.call(
        payload.merge("participant" => [
                        { "type" => [{ "coding" => [{ "code" => "ATND" }] }], "status" => "needs-action" }
                      ])
      )

      expect(result).to be_valid
      # No Patient participant, so it belongs to no compartment -- a warning, not an error.
      expect(result.warnings.first[:code]).to eq("informational")
    end

    it "rejects a participant with no status" do
      result = described_class.call(
        payload.merge("participant" => [{ "actor" => { "reference" => "Practitioner/pr1" } }])
      )

      expect(result).not_to be_valid
      expect(result.errors.first[:expression]).to eq(["Appointment.participant[0].status"])
    end

    it "rejects a participant status outside the participationstatus ValueSet" do
      result = described_class.call(
        payload.merge("participant" => [
                        { "actor" => { "reference" => "Practitioner/pr1" }, "status" => "confirmed" }
                      ])
      )

      expect(result).not_to be_valid
      expect(result.errors.first[:code]).to eq("value")
    end

    it "rejects a participant required value outside the participantrequired ValueSet" do
      result = described_class.call(
        payload.merge("participant" => [
                        { "actor" => { "reference" => "Practitioner/pr1" },
                          "required" => "mandatory", "status" => "accepted" }
                      ])
      )

      expect(result).not_to be_valid
      expect(result.errors.first[:code]).to eq("value")
    end
  end

  describe "the Patient participant" do
    it "warns (rather than rejecting) when no participant is a Patient" do
      result = described_class.call(
        payload.merge("participant" => [
                        { "actor" => { "reference" => "Practitioner/pr1" }, "status" => "accepted" }
                      ])
      )

      expect(result).to be_valid
      expect(result.warnings.first[:diagnostics]).to include("patient compartment")
    end

    it "rejects a Patient participant that does not exist" do
      result = described_class.call(
        payload.merge("participant" => [
                        { "actor" => { "reference" => "Patient/does-not-exist" }, "status" => "accepted" }
                      ])
      )

      expect(result).not_to be_valid
      expect(result.errors.first[:code]).to eq("invalid")
    end
  end
end
