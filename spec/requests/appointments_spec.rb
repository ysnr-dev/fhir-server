require "rails_helper"

RSpec.describe "Appointments", type: :request do
  def create_patient
    post "/Patient", params: valid_patient_payload, as: :json
    JSON.parse(response.body)["id"]
  end

  def create_practitioner
    post "/Practitioner", params: valid_practitioner_payload, as: :json
    JSON.parse(response.body)["id"]
  end

  def create_location
    post "/Location", params: valid_location_payload, as: :json
    JSON.parse(response.body)["id"]
  end

  def create_service_request(subject_id:)
    post "/ServiceRequest", params: valid_service_request_payload(subject_id: subject_id), as: :json
    JSON.parse(response.body)["id"]
  end

  def create_slot
    post "/Schedule", params: valid_schedule_payload(actor_id: create_practitioner), as: :json
    schedule_id = JSON.parse(response.body)["id"]
    post "/Slot", params: valid_slot_payload(schedule_id: schedule_id), as: :json
    expect(response).to have_http_status(:created), "setup failed: #{response.body}"
    JSON.parse(response.body)["id"]
  end

  def create_appointment(**args)
    post "/Appointment", params: valid_appointment_payload(**args), as: :json
    expect(response).to have_http_status(:created), "setup failed: #{response.body}"
    JSON.parse(response.body)["id"]
  end

  describe "POST /Appointment" do
    it "creates and returns 201 with Location, ETag, and meta" do
      patient_id = create_patient

      post "/Appointment", params: valid_appointment_payload(patient_id: patient_id), as: :json

      expect(response).to have_http_status(:created)
      expect(response.content_type).to include("application/fhir+json")
      expect(response.headers["Location"]).to match(%r{/Appointment/[\w-]+/_history/1\z})
      expect(response.headers["ETag"]).to eq('W/"1"')

      body = JSON.parse(response.body)
      expect(body["resourceType"]).to eq("Appointment")
      # JP Core does not profile Appointment, so the bare HL7 base profile is stamped.
      expect(body["meta"]["profile"]).to eq(["http://hl7.org/fhir/StructureDefinition/Appointment"])
    end

    it "returns 422 for a status outside the appointmentstatus ValueSet" do
      post "/Appointment", params: valid_appointment_payload(status: "free"), as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "returns 422 when a booked appointment has no start or end (app-3)" do
      payload = valid_appointment_payload.except("start", "end")

      post "/Appointment", params: payload, as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "returns 422 when participant is absent" do
      post "/Appointment", params: valid_appointment_payload.except("participant"), as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "returns 422 when a participant actor references a non-existent patient" do
      post "/Appointment", params: valid_appointment_payload(patient_id: "does-not-exist"), as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "GET /Appointment/:id" do
    it "returns the resource" do
      id = create_appointment(patient_id: create_patient)

      get "/Appointment/#{id}"

      expect(response).to have_http_status(:ok)
    end

    it "returns 404 for an unknown id" do
      get "/Appointment/does-not-exist"

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "PUT and DELETE" do
    it "checks the patient in and then deletes the appointment" do
      patient_id = create_patient
      id = create_appointment(patient_id: patient_id)

      put "/Appointment/#{id}",
          params: valid_appointment_payload(patient_id: patient_id, status: "arrived"), as: :json
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["meta"]["versionId"]).to eq("2")

      delete "/Appointment/#{id}"
      expect(response).to have_http_status(:no_content)

      get "/Appointment/#{id}"
      expect(response).to have_http_status(:gone)
    end
  end

  describe "GET /Appointment (search)" do
    it "finds by identifier" do
      create_appointment(patient_id: create_patient)

      get "/Appointment", params: { identifier: "APT1" }

      bundle = JSON.parse(response.body)
      expect(bundle["type"]).to eq("searchset")
      expect(bundle["total"]).to eq(1)
    end

    # The patient's own booking list: their appointments on a given day.
    it "finds one patient's appointments within a date window" do
      patient_id = create_patient
      create_appointment(patient_id: patient_id)
      create_appointment(patient_id: patient_id,
                         start: "2026-09-03T09:00:00+09:00", end: "2026-09-03T09:30:00+09:00")
      create_appointment(patient_id: create_patient)

      get "/Appointment?patient=Patient/#{patient_id}&date=ge2026-09-01&date=lt2026-09-02"

      expect(JSON.parse(response.body)["total"]).to eq(1)
    end

    it "finds by status and appointment-type" do
      create_appointment(patient_id: create_patient)

      get "/Appointment", params: { status: "booked",
                                    "appointment-type" => "http://terminology.hl7.org/CodeSystem/v2-0276|ROUTINE" }

      expect(JSON.parse(response.body)["total"]).to eq(1)
    end

    # part-status lives inside the repeating participant element, and answers the
    # question status alone cannot: who has not confirmed yet.
    it "finds appointments awaiting a participant's confirmation by part-status" do
      patient_id = create_patient
      create_appointment(patient_id: patient_id)
      create_appointment(
        participant: [{ "actor" => { "reference" => "Practitioner/#{create_practitioner}" },
                        "status" => "needs-action" }]
      )

      get "/Appointment", params: { "part-status" => "needs-action" }
      expect(JSON.parse(response.body)["total"]).to eq(1)

      get "/Appointment", params: { "part-status" => "accepted" }
      expect(JSON.parse(response.body)["total"]).to eq(1)
    end

    # patient / practitioner / location all read the same participant array; the
    # target type is what separates them.
    it "finds by practitioner and by location" do
      practitioner_id = create_practitioner
      location_id = create_location
      create_appointment(patient_id: create_patient, practitioner_id: practitioner_id, location_id: location_id)
      create_appointment(patient_id: create_patient)

      get "/Appointment", params: { practitioner: "Practitioner/#{practitioner_id}" }
      expect(JSON.parse(response.body)["total"]).to eq(1)

      get "/Appointment", params: { location: "Location/#{location_id}" }
      expect(JSON.parse(response.body)["total"]).to eq(1)
    end

    it "finds by slot and by based-on" do
      patient_id = create_patient
      slot_id = create_slot
      service_request_id = create_service_request(subject_id: patient_id)
      create_appointment(patient_id: patient_id, slot_id: slot_id, service_request_id: service_request_id)
      create_appointment(patient_id: patient_id)

      get "/Appointment", params: { slot: "Slot/#{slot_id}" }
      expect(JSON.parse(response.body)["total"]).to eq(1)

      get "/Appointment", params: { "based-on" => "ServiceRequest/#{service_request_id}" }
      expect(JSON.parse(response.body)["total"]).to eq(1)
    end

    it "chains to the patient's name" do
      create_appointment(patient_id: create_patient)

      get "/Appointment", params: { "patient.name" => "山田" }

      expect(JSON.parse(response.body)["total"]).to eq(1)
    end

    # The booking screen's typical read: the appointment plus who and what it is for.
    it "includes the participants with _include" do
      patient_id = create_patient
      practitioner_id = create_practitioner
      create_appointment(patient_id: patient_id, practitioner_id: practitioner_id)

      get "/Appointment", params: { _include: "Appointment:actor" }

      types = JSON.parse(response.body)["entry"].map { |e| e.dig("resource", "resourceType") }
      expect(types).to include("Appointment", "Patient", "Practitioner")
    end

    it "brings a slot's appointment along with _revinclude" do
      slot_id = create_slot
      create_appointment(patient_id: create_patient, slot_id: slot_id)

      get "/Slot", params: { _id: slot_id, _revinclude: "Appointment:slot" }

      types = JSON.parse(response.body)["entry"].map { |e| e.dig("resource", "resourceType") }
      expect(types).to include("Slot", "Appointment")
    end
  end

  describe "the patient compartment" do
    # Appointment has no single-valued Patient element, so compartment membership
    # rests on the patient_reference column flattened out of participant.
    it "includes the appointment in Patient/$everything" do
      patient_id = create_patient
      create_appointment(patient_id: patient_id)

      get "/Patient/#{patient_id}/$everything"

      types = JSON.parse(response.body)["entry"].map { |e| e.dig("resource", "resourceType") }
      expect(types).to include("Appointment")
    end

    it "leaves an appointment with no Patient participant out of the compartment" do
      patient_id = create_patient
      create_appointment(practitioner_id: create_practitioner)

      get "/Patient/#{patient_id}/$everything"

      types = JSON.parse(response.body)["entry"].map { |e| e.dig("resource", "resourceType") }
      expect(types).not_to include("Appointment")
    end
  end
end
