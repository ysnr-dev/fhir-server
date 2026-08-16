require "rails_helper"

RSpec.describe "Schedules", type: :request do
  def create_practitioner
    post "/Practitioner", params: valid_practitioner_payload, as: :json
    JSON.parse(response.body)["id"]
  end

  def create_location
    post "/Location", params: valid_location_payload, as: :json
    JSON.parse(response.body)["id"]
  end

  def create_schedule(**args)
    post "/Schedule", params: valid_schedule_payload(**args), as: :json
    expect(response).to have_http_status(:created), "setup failed: #{response.body}"
    JSON.parse(response.body)["id"]
  end

  describe "POST /Schedule" do
    it "creates and returns 201 with Location, ETag, and meta" do
      post "/Schedule", params: valid_schedule_payload(actor_id: create_practitioner), as: :json

      expect(response).to have_http_status(:created)
      expect(response.content_type).to include("application/fhir+json")
      expect(response.headers["Location"]).to match(%r{/Schedule/[\w-]+/_history/1\z})
      expect(response.headers["ETag"]).to eq('W/"1"')

      body = JSON.parse(response.body)
      expect(body["resourceType"]).to eq("Schedule")
      # JP Core does not profile Schedule, so the bare HL7 base profile is stamped.
      expect(body["meta"]["profile"]).to eq(["http://hl7.org/fhir/StructureDefinition/Schedule"])
    end

    it "returns 422 when actor is absent" do
      payload = valid_schedule_payload(actor_id: "pr1").except("actor")

      post "/Schedule", params: payload, as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "returns 422 when the planning horizon ends before it starts" do
      payload = valid_schedule_payload(actor_id: "pr1").merge(
        "planningHorizon" => { "start" => "2026-09-30T00:00:00+09:00", "end" => "2026-09-01T00:00:00+09:00" }
      )

      post "/Schedule", params: payload, as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "GET /Schedule/:id" do
    it "returns the resource" do
      id = create_schedule(actor_id: create_practitioner)

      get "/Schedule/#{id}"

      expect(response).to have_http_status(:ok)
    end

    it "returns 404 for an unknown id" do
      get "/Schedule/does-not-exist"

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "PUT and DELETE" do
    it "retires the schedule and then deletes it" do
      practitioner_id = create_practitioner
      id = create_schedule(actor_id: practitioner_id)

      put "/Schedule/#{id}", params: valid_schedule_payload(actor_id: practitioner_id, active: false), as: :json
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["meta"]["versionId"]).to eq("2")

      delete "/Schedule/#{id}"
      expect(response).to have_http_status(:no_content)

      get "/Schedule/#{id}"
      expect(response).to have_http_status(:gone)
    end
  end

  describe "GET /Schedule (search)" do
    it "finds by identifier" do
      create_schedule(actor_id: create_practitioner)

      get "/Schedule", params: { identifier: "SCH1" }

      bundle = JSON.parse(response.body)
      expect(bundle["type"]).to eq("searchset")
      expect(bundle["total"]).to eq(1)
    end

    # A retired schedule stays readable but must not surface in the booking screen.
    it "separates active from retired schedules" do
      practitioner_id = create_practitioner
      create_schedule(actor_id: practitioner_id)
      create_schedule(actor_id: practitioner_id, active: false)

      get "/Schedule", params: { active: "true" }
      expect(JSON.parse(response.body)["total"]).to eq(1)

      get "/Schedule", params: { active: "false" }
      expect(JSON.parse(response.body)["total"]).to eq(1)
    end

    it "finds by actor, whether the actor is a practitioner or a room" do
      practitioner_id = create_practitioner
      location_id = create_location
      create_schedule(actor_id: practitioner_id)
      create_schedule(actor_id: location_id, actor_type: "Location")

      get "/Schedule", params: { actor: "Practitioner/#{practitioner_id}" }
      expect(JSON.parse(response.body)["total"]).to eq(1)

      get "/Schedule", params: { actor: "Location/#{location_id}" }
      expect(JSON.parse(response.body)["total"]).to eq(1)
    end

    it "finds by service-type and specialty with system|code" do
      create_schedule(actor_id: create_practitioner)

      get "/Schedule", params: { "service-type" => "http://example.org/CodeSystem/service-type|outpatient",
                                 "specialty" => "http://snomed.info/sct|419192003" }

      expect(JSON.parse(response.body)["total"]).to eq(1)
    end

    # `date` searches planningHorizon as a period: eq is containment, so a horizon
    # covering all of September is found by a query inside it, not by one outside.
    it "finds by a date inside the planning horizon" do
      create_schedule(actor_id: create_practitioner)

      get "/Schedule", params: { date: "ge2026-09-15" }
      expect(JSON.parse(response.body)["total"]).to eq(1)

      get "/Schedule", params: { date: "gt2026-10-31" }
      expect(JSON.parse(response.body)["total"]).to eq(0)
    end

    it "chains to the actor's name" do
      create_schedule(actor_id: create_practitioner)

      get "/Schedule", params: { "actor.name" => "鈴木" }

      expect(JSON.parse(response.body)["total"]).to eq(1)
    end

    it "includes the actor with _include" do
      practitioner_id = create_practitioner
      create_schedule(actor_id: practitioner_id)

      get "/Schedule", params: { _include: "Schedule:actor" }

      types = JSON.parse(response.body)["entry"].map { |e| e.dig("resource", "resourceType") }
      expect(types).to include("Schedule", "Practitioner")
    end
  end
end
