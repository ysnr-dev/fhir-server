module AppointmentPayloadHelper
  # A Schedule is the calendar a practitioner or a room offers slots on: actor is
  # 1..* and required, so every caller passes at least one.
  def valid_schedule_payload(actor_id: nil, actor_type: "Practitioner", **overrides)
    {
      "resourceType" => "Schedule",
      "identifier" => [{ "system" => "http://example.org/schedule", "value" => "SCH1" }],
      "active" => true,
      "serviceCategory" => [
        { "coding" => [{ "system" => "http://terminology.hl7.org/CodeSystem/service-category",
                         "code" => "17", "display" => "General Practice" }] }
      ],
      "serviceType" => [
        { "coding" => [{ "system" => "http://example.org/CodeSystem/service-type", "code" => "outpatient" }],
          "text" => "一般外来" }
      ],
      "specialty" => [
        { "coding" => [{ "system" => "http://snomed.info/sct", "code" => "419192003" }], "text" => "内科" }
      ],
      "actor" => [{ "reference" => "#{actor_type}/#{actor_id}" }],
      "planningHorizon" => { "start" => "2026-09-01T00:00:00+09:00", "end" => "2026-09-30T23:59:59+09:00" },
      "comment" => "内科 一般外来の診療枠"
    }.deep_merge(overrides.deep_stringify_keys)
  end

  # One bookable opening on a Schedule. start/end are FHIR `instant`s, so a
  # timezone offset is mandatory.
  def valid_slot_payload(schedule_id: nil, **overrides)
    {
      "resourceType" => "Slot",
      "identifier" => [{ "system" => "http://example.org/slot", "value" => "SLT1" }],
      "serviceCategory" => [
        { "coding" => [{ "system" => "http://terminology.hl7.org/CodeSystem/service-category", "code" => "17" }] }
      ],
      "serviceType" => [
        { "coding" => [{ "system" => "http://example.org/CodeSystem/service-type", "code" => "outpatient" }] }
      ],
      "specialty" => [{ "coding" => [{ "system" => "http://snomed.info/sct", "code" => "419192003" }] }],
      "appointmentType" => {
        "coding" => [{ "system" => "http://terminology.hl7.org/CodeSystem/v2-0276", "code" => "ROUTINE" }]
      },
      "schedule" => { "reference" => "Schedule/#{schedule_id}" },
      "status" => "free",
      "start" => "2026-09-01T09:00:00+09:00",
      "end" => "2026-09-01T09:30:00+09:00",
      "overbooked" => false
    }.deep_merge(overrides.deep_stringify_keys)
  end

  # A booking: the patient and the practitioner are both participants, `slot`
  # points at the opening it consumed. Pass patient_id: nil for an appointment
  # with no patient compartment (the validator warns rather than rejecting).
  def valid_appointment_payload(patient_id: nil, practitioner_id: nil, location_id: nil,
                                slot_id: nil, service_request_id: nil, condition_id: nil, **overrides)
    participants = []
    if patient_id
      participants << { "actor" => { "reference" => "Patient/#{patient_id}" },
                        "required" => "required", "status" => "accepted" }
    end
    if practitioner_id
      participants << { "actor" => { "reference" => "Practitioner/#{practitioner_id}" },
                        "required" => "required", "status" => "accepted" }
    end
    if location_id
      participants << { "actor" => { "reference" => "Location/#{location_id}" },
                        "required" => "required", "status" => "accepted" }
    end
    # participant is 1..* -- fall back to a type-only entry (app-1 allows it).
    if participants.empty?
      participants << {
        "type" => [{ "coding" => [{ "system" => "http://terminology.hl7.org/CodeSystem/v3-ParticipationType",
                                    "code" => "ATND" }] }],
        "status" => "needs-action"
      }
    end

    payload = {
      "resourceType" => "Appointment",
      "identifier" => [{ "system" => "http://example.org/appointment", "value" => "APT1" }],
      "status" => "booked",
      "serviceCategory" => [
        { "coding" => [{ "system" => "http://terminology.hl7.org/CodeSystem/service-category", "code" => "17" }] }
      ],
      "serviceType" => [
        { "coding" => [{ "system" => "http://example.org/CodeSystem/service-type", "code" => "outpatient" }] }
      ],
      "specialty" => [{ "coding" => [{ "system" => "http://snomed.info/sct", "code" => "419192003" }] }],
      "appointmentType" => {
        "coding" => [{ "system" => "http://terminology.hl7.org/CodeSystem/v2-0276", "code" => "ROUTINE" }]
      },
      "reasonCode" => [
        { "coding" => [{ "system" => "http://snomed.info/sct", "code" => "162864005" }], "text" => "経過観察" }
      ],
      "description" => "内科 再診",
      "start" => "2026-09-01T09:00:00+09:00",
      "end" => "2026-09-01T09:30:00+09:00",
      "minutesDuration" => 30,
      "created" => "2026-08-16T10:00:00+09:00",
      "comment" => "初回来院は 15 分前にお越しください",
      "participant" => participants
    }
    payload["slot"] = [{ "reference" => "Slot/#{slot_id}" }] if slot_id
    payload["basedOn"] = [{ "reference" => "ServiceRequest/#{service_request_id}" }] if service_request_id
    payload["reasonReference"] = [{ "reference" => "Condition/#{condition_id}" }] if condition_id

    payload.deep_merge(overrides.deep_stringify_keys)
  end
end

RSpec.configure do |config|
  config.include AppointmentPayloadHelper, type: :request
end
