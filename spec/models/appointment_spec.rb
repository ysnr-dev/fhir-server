require "rails_helper"

RSpec.describe Appointment do
  def build_appointment(content)
    described_class.new(
      id: SecureRandom.uuid,
      version_id: 1,
      content: content,
      last_updated: Time.current
    )
  end

  describe "#sync_search_fields!" do
    it "extracts status, appointment type, start, and the Patient participant" do
      appointment = build_appointment(
        "status" => "booked",
        "appointmentType" => { "coding" => [{ "code" => "ROUTINE" }] },
        "start" => "2026-09-01T09:00:00+09:00",
        "end" => "2026-09-01T09:30:00+09:00",
        "participant" => [
          { "actor" => { "reference" => "Practitioner/pr1" }, "status" => "accepted" },
          { "actor" => { "reference" => "Patient/p1" }, "status" => "accepted" },
          { "actor" => { "reference" => "Location/l1" }, "status" => "accepted" }
        ]
      )

      appointment.sync_search_fields!

      expect(appointment.status).to eq("booked")
      expect(appointment.appointment_type).to eq("ROUTINE")
      expect(appointment.start_time).to eq(Time.iso8601("2026-09-01T09:00:00+09:00"))
      # The Patient is picked out of the participant array regardless of position:
      # it is what puts the Appointment in a patient compartment.
      expect(appointment.patient_reference).to eq("Patient/p1")
    end

    it "leaves patient_reference nil when no participant is a Patient" do
      appointment = build_appointment(
        "status" => "booked",
        "participant" => [
          { "actor" => { "reference" => "Practitioner/pr1" }, "status" => "accepted" },
          { "type" => [{ "coding" => [{ "code" => "ATND" }] }], "status" => "needs-action" }
        ]
      )

      appointment.sync_search_fields!

      expect(appointment.patient_reference).to be_nil
    end

    # slot / basedOn / reasonReference are 0..* and searched by jsonb containment,
    # so they must NOT acquire a column.
    it "leaves the repeating references in content only" do
      appointment = build_appointment(
        "status" => "booked",
        "slot" => [{ "reference" => "Slot/s1" }, { "reference" => "Slot/s2" }],
        "basedOn" => [{ "reference" => "ServiceRequest/sr1" }],
        "reasonReference" => [{ "reference" => "Condition/c1" }]
      )

      appointment.sync_search_fields!

      expect(described_class.column_names).not_to include("slot_reference", "based_on_reference")
      expect(appointment.content["slot"].size).to eq(2)
    end

    it "is nil-safe when fields are absent" do
      appointment = build_appointment({})

      expect { appointment.sync_search_fields! }.not_to raise_error
      expect(appointment.status).to be_nil
      expect(appointment.patient_reference).to be_nil
      expect(appointment.start_time).to be_nil
    end
  end

  describe "#sync_tokens!" do
    it "emits rows for status, appointmentType, the service concepts, reasonCode, and each participant status" do
      appointment = build_appointment(
        "status" => "pending",
        "appointmentType" => {
          "coding" => [{ "system" => "http://terminology.hl7.org/CodeSystem/v2-0276", "code" => "ROUTINE" }]
        },
        "serviceCategory" => [{ "coding" => [{ "system" => "http://example.org/cat", "code" => "17" }] }],
        "serviceType" => [{ "coding" => [{ "system" => "http://example.org/type", "code" => "outpatient" }] }],
        "specialty" => [{ "coding" => [{ "system" => "http://snomed.info/sct", "code" => "419192003" }] }],
        "reasonCode" => [{ "coding" => [{ "system" => "http://snomed.info/sct", "code" => "162864005" }] }],
        "participant" => [
          { "actor" => { "reference" => "Patient/p1" }, "status" => "needs-action" },
          { "actor" => { "reference" => "Practitioner/pr1" }, "status" => "accepted" }
        ]
      )

      appointment.save!(validate: false)
      appointment.sync_tokens!

      expect(appointment.resource_tokens.where(param_name: "status").pluck(:code)).to eq(["pending"])
      expect(appointment.resource_tokens.where(param_name: "appointment-type").pluck(:code)).to eq(["ROUTINE"])
      expect(appointment.resource_tokens.where(param_name: "service-category").pluck(:code)).to eq(["17"])
      expect(appointment.resource_tokens.where(param_name: "service-type").pluck(:code)).to eq(["outpatient"])
      expect(appointment.resource_tokens.where(param_name: "specialty").pluck(:code)).to eq(["419192003"])
      expect(appointment.resource_tokens.where(param_name: "reason-code").pluck(:code)).to eq(["162864005"])
      # participant.status lives inside a repeating backbone element -- one token
      # row per participant, so "誰かの承諾待ち" is answerable by part-status.
      expect(appointment.resource_tokens.where(param_name: "part-status").pluck(:code))
        .to contain_exactly("needs-action", "accepted")
    end
  end
end
