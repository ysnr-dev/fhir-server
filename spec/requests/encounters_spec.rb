require "rails_helper"

RSpec.describe "Encounters", type: :request do
  describe "POST /Encounter" do
    it "creates and returns 201 with Location header, ETag, and meta" do
      post "/Encounter", params: valid_encounter_payload, as: :json

      expect(response).to have_http_status(:created)
      expect(response.headers["Location"]).to match(%r{/Encounter/[\w-]+/_history/1\z})
      expect(response.headers["ETag"]).to eq('W/"1"')

      body = JSON.parse(response.body)
      expect(body["resourceType"]).to eq("Encounter")
    end

    it "returns 422 when status is missing" do
      post "/Encounter", params: valid_encounter_payload.except("status"), as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "returns 422 when class is missing" do
      post "/Encounter", params: valid_encounter_payload.except("class"), as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "read, update, delete, history" do
    it "supports the full lifecycle" do
      post "/Encounter", params: valid_encounter_payload, as: :json
      id = JSON.parse(response.body)["id"]

      get "/Encounter/#{id}"
      expect(response).to have_http_status(:ok)

      put "/Encounter/#{id}", params: valid_encounter_payload(status: "cancelled"), as: :json
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["meta"]["versionId"]).to eq("2")

      delete "/Encounter/#{id}"
      expect(response).to have_http_status(:no_content)

      get "/Encounter/#{id}/_history"
      expect(JSON.parse(response.body)["total"]).to eq(3)
    end
  end

  describe "GET /Encounter (search)" do
    it "filters by status and class" do
      post "/Encounter", params: valid_encounter_payload(status: "in-progress"), as: :json

      get "/Encounter", params: { status: "in-progress", class: "AMB" }

      bundle = JSON.parse(response.body)
      expect(bundle["type"]).to eq("searchset")
      expect(bundle["total"]).to be >= 1
    end

    it "finds by patient reference (subject alias)" do
      patient_id = SecureRandom.uuid
      post "/Encounter",
           params: valid_encounter_payload(subject: { "reference" => "Patient/#{patient_id}" }),
           as: :json

      get "/Encounter", params: { patient: patient_id }

      expect(JSON.parse(response.body)["total"]).to eq(1)
    end

    it "matches a day-precision date search that fully contains the period (eq)" do
      identifier = SecureRandom.hex(6)
      post "/Encounter",
           params: valid_encounter_payload(
             identifier: [{ "system" => "http://example.org/encounter", "value" => identifier }],
             period: { "start" => "2026-07-19T09:00:00+09:00", "end" => "2026-07-19T10:00:00+09:00" }
           ),
           as: :json

      get "/Encounter", params: { identifier: identifier, date: "2026-07-19" }
      expect(JSON.parse(response.body)["total"]).to eq(1)

      get "/Encounter", params: { identifier: identifier, date: "2026-07-18" }
      expect(JSON.parse(response.body)["total"]).to eq(0)
    end

    it "matches an ongoing encounter (no period.end) with a ge search" do
      identifier = SecureRandom.hex(6)
      post "/Encounter",
           params: valid_encounter_payload(
             identifier: [{ "system" => "http://example.org/encounter", "value" => identifier }],
             period: { "start" => "2026-07-19T09:00:00+09:00", "end" => nil }
           ),
           as: :json

      get "/Encounter", params: { identifier: identifier, date: "ge2000-01-01" }
      expect(JSON.parse(response.body)["total"]).to eq(1)

      get "/Encounter", params: { identifier: identifier, date: "lt2000-01-01" }
      expect(JSON.parse(response.body)["total"]).to eq(0)
    end

    it "sorts by date using period.start" do
      earlier = SecureRandom.hex(6)
      later = SecureRandom.hex(6)
      post "/Encounter",
           params: valid_encounter_payload(identifier: [{ "system" => "http://example.org/encounter", "value" => later }],
                                            period: { "start" => "2026-07-20T00:00:00Z", "end" => nil }),
           as: :json
      post "/Encounter",
           params: valid_encounter_payload(identifier: [{ "system" => "http://example.org/encounter", "value" => earlier }],
                                            period: { "start" => "2026-07-01T00:00:00Z", "end" => nil }),
           as: :json

      get "/Encounter", params: { identifier: "#{earlier},#{later}", _sort: "date" }

      values = JSON.parse(response.body)["entry"].map { |e| e["resource"]["identifier"].first["value"] }
      expect(values).to eq([earlier, later])
    end
  end
end
