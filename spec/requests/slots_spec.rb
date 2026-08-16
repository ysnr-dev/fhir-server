require "rails_helper"

RSpec.describe "Slots", type: :request do
  def create_practitioner
    post "/Practitioner", params: valid_practitioner_payload, as: :json
    JSON.parse(response.body)["id"]
  end

  def create_schedule
    post "/Schedule", params: valid_schedule_payload(actor_id: create_practitioner), as: :json
    expect(response).to have_http_status(:created), "setup failed: #{response.body}"
    JSON.parse(response.body)["id"]
  end

  def create_slot(**args)
    post "/Slot", params: valid_slot_payload(**args), as: :json
    expect(response).to have_http_status(:created), "setup failed: #{response.body}"
    JSON.parse(response.body)["id"]
  end

  describe "POST /Slot" do
    it "creates and returns 201 with Location, ETag, and meta" do
      post "/Slot", params: valid_slot_payload(schedule_id: create_schedule), as: :json

      expect(response).to have_http_status(:created)
      expect(response.content_type).to include("application/fhir+json")
      expect(response.headers["Location"]).to match(%r{/Slot/[\w-]+/_history/1\z})
      expect(response.headers["ETag"]).to eq('W/"1"')

      body = JSON.parse(response.body)
      expect(body["resourceType"]).to eq("Slot")
      # JP Core does not profile Slot, so the bare HL7 base profile is stamped.
      expect(body["meta"]["profile"]).to eq(["http://hl7.org/fhir/StructureDefinition/Slot"])
    end

    it "returns 422 for a status outside the slot-status ValueSet" do
      post "/Slot", params: valid_slot_payload(schedule_id: "sch1", status: "booked"), as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "returns 422 when schedule is absent" do
      post "/Slot", params: valid_slot_payload(schedule_id: "sch1").except("schedule"), as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end

    # start/end are `instant`: a value with no timezone offset would be read
    # against the server's clock and silently shift the slot.
    it "returns 422 for a start with no timezone offset" do
      post "/Slot", params: valid_slot_payload(schedule_id: "sch1", start: "2026-09-01T09:00:00"), as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "returns 422 when end precedes start" do
      post "/Slot", params: valid_slot_payload(schedule_id: "sch1", end: "2026-09-01T08:30:00+09:00"), as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "GET /Slot/:id" do
    it "returns the resource" do
      id = create_slot(schedule_id: create_schedule)

      get "/Slot/#{id}"

      expect(response).to have_http_status(:ok)
    end

    it "returns 404 for an unknown id" do
      get "/Slot/does-not-exist"

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "PUT and DELETE" do
    it "marks the slot busy once booked and then deletes it" do
      schedule_id = create_schedule
      id = create_slot(schedule_id: schedule_id)

      put "/Slot/#{id}", params: valid_slot_payload(schedule_id: schedule_id, status: "busy"), as: :json
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["meta"]["versionId"]).to eq("2")

      delete "/Slot/#{id}"
      expect(response).to have_http_status(:no_content)

      get "/Slot/#{id}"
      expect(response).to have_http_status(:gone)
    end
  end

  describe "GET /Slot (search)" do
    it "finds by identifier" do
      create_slot(schedule_id: create_schedule)

      get "/Slot", params: { identifier: "SLT1" }

      bundle = JSON.parse(response.body)
      expect(bundle["type"]).to eq("searchset")
      expect(bundle["total"]).to eq(1)
    end

    # The booking screen's one query: free openings on this schedule, that day.
    it "finds the free slots of one schedule within a time window" do
      schedule_id = create_schedule
      create_slot(schedule_id: schedule_id)
      create_slot(schedule_id: schedule_id, status: "busy",
                  start: "2026-09-01T10:00:00+09:00", end: "2026-09-01T10:30:00+09:00")
      create_slot(schedule_id: schedule_id,
                  start: "2026-09-03T09:00:00+09:00", end: "2026-09-03T09:30:00+09:00")

      # Repeated `start` ANDs into a window; written as a raw query string because
      # a params Hash cannot express the same key twice.
      get "/Slot?schedule=Schedule/#{schedule_id}&status=free&start=ge2026-09-01&start=lt2026-09-02"

      bundle = JSON.parse(response.body)
      expect(bundle["total"]).to eq(1)
      expect(bundle["entry"].first.dig("resource", "start")).to eq("2026-09-01T09:00:00+09:00")
    end

    it "finds by appointment-type and specialty with system|code" do
      create_slot(schedule_id: create_schedule)

      get "/Slot", params: { "appointment-type" => "http://terminology.hl7.org/CodeSystem/v2-0276|ROUTINE",
                             "specialty" => "http://snomed.info/sct|419192003" }

      expect(JSON.parse(response.body)["total"]).to eq(1)
    end

    it "sorts by start" do
      schedule_id = create_schedule
      create_slot(schedule_id: schedule_id,
                  start: "2026-09-01T11:00:00+09:00", end: "2026-09-01T11:30:00+09:00")
      create_slot(schedule_id: schedule_id)

      get "/Slot", params: { _sort: "start" }

      starts = JSON.parse(response.body)["entry"].map { |e| e.dig("resource", "start") }
      expect(starts).to eq(["2026-09-01T09:00:00+09:00", "2026-09-01T11:00:00+09:00"])
    end

    it "includes the schedule with _include and its slots with _revinclude" do
      schedule_id = create_schedule
      create_slot(schedule_id: schedule_id)

      get "/Slot", params: { _include: "Slot:schedule" }
      types = JSON.parse(response.body)["entry"].map { |e| e.dig("resource", "resourceType") }
      expect(types).to include("Slot", "Schedule")

      get "/Schedule", params: { _id: schedule_id, _revinclude: "Slot:schedule" }
      types = JSON.parse(response.body)["entry"].map { |e| e.dig("resource", "resourceType") }
      expect(types).to include("Schedule", "Slot")
    end

    # The other direction of the same link: which schedules have a free slot left.
    it "finds schedules by _has on their slots" do
      schedule_id = create_schedule
      create_slot(schedule_id: schedule_id, status: "busy")

      get "/Schedule", params: { "_has:Slot:schedule:status" => "free" }
      expect(JSON.parse(response.body)["total"]).to eq(0)

      get "/Schedule", params: { "_has:Slot:schedule:status" => "busy" }
      expect(JSON.parse(response.body)["total"]).to eq(1)
    end
  end
end
