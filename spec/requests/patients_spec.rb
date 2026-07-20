require "rails_helper"

RSpec.describe "Patients", type: :request do
  describe "POST /Patient" do
    it "creates a patient and returns 201 with Location, ETag, and meta" do
      post "/Patient", params: valid_patient_payload, as: :json

      expect(response).to have_http_status(:created)
      expect(response.content_type).to include("application/fhir+json")
      expect(response.headers["Location"]).to match(%r{/Patient/[\w-]+/_history/1\z})
      expect(response.headers["ETag"]).to eq('W/"1"')

      body = JSON.parse(response.body)
      expect(body["resourceType"]).to eq("Patient")
      expect(body["id"]).to be_present
      expect(body["meta"]["versionId"]).to eq("1")
      expect(body["meta"]["lastUpdated"]).to be_present
    end

    it "returns 422 when identifier is missing (JP Core 1..*)" do
      post "/Patient", params: valid_patient_payload.except("identifier"), as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      body = JSON.parse(response.body)
      expect(body["resourceType"]).to eq("OperationOutcome")
      expect(body["issue"]).to include(hash_including("code" => "required"))
    end

    it "returns 422 for an invalid gender value" do
      post "/Patient", params: valid_patient_payload(gender: "invalid"), as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      body = JSON.parse(response.body)
      expect(body["issue"]).to include(hash_including("code" => "value"))
    end

    it "returns 422 for a malformed birthDate" do
      post "/Patient", params: valid_patient_payload(birthDate: "not-a-date"), as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "returns 422 for an impossible calendar date" do
      post "/Patient", params: valid_patient_payload(birthDate: "2020-13-40"), as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "returns 400 when resourceType does not match" do
      post "/Patient", params: valid_patient_payload.merge("resourceType" => "Observation"), as: :json

      expect(response).to have_http_status(:bad_request)
      expect(JSON.parse(response.body)["resourceType"]).to eq("OperationOutcome")
    end

    it "returns 400 for malformed JSON" do
      post "/Patient", params: "{not valid json", headers: { "CONTENT_TYPE" => "application/fhir+json" }

      expect(response).to have_http_status(:bad_request)
    end
  end

  describe "GET /Patient/:id" do
    it "returns the patient with ETag" do
      post "/Patient", params: valid_patient_payload, as: :json
      id = JSON.parse(response.body)["id"]

      get "/Patient/#{id}"

      expect(response).to have_http_status(:ok)
      expect(response.headers["ETag"]).to eq('W/"1"')
      expect(JSON.parse(response.body)["id"]).to eq(id)
    end

    it "returns 404 for an unknown id" do
      get "/Patient/does-not-exist"

      expect(response).to have_http_status(:not_found)
      expect(JSON.parse(response.body)["resourceType"]).to eq("OperationOutcome")
    end

    it "returns 410 for a deleted patient" do
      post "/Patient", params: valid_patient_payload, as: :json
      id = JSON.parse(response.body)["id"]
      delete "/Patient/#{id}"

      get "/Patient/#{id}"

      expect(response).to have_http_status(:gone)
    end
  end

  describe "PUT /Patient/:id" do
    it "updates the patient and increments the version" do
      post "/Patient", params: valid_patient_payload, as: :json
      id = JSON.parse(response.body)["id"]

      put "/Patient/#{id}", params: valid_patient_payload(gender: "female"), as: :json

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["gender"]).to eq("female")
      expect(body["meta"]["versionId"]).to eq("2")
      expect(response.headers["ETag"]).to eq('W/"2"')
    end

    it "returns 412 when If-Match does not match the current version" do
      post "/Patient", params: valid_patient_payload, as: :json
      id = JSON.parse(response.body)["id"]

      put "/Patient/#{id}", params: valid_patient_payload, headers: { "If-Match" => 'W/"99"' }, as: :json

      expect(response).to have_http_status(:precondition_failed)
    end

    it "succeeds when If-Match matches the current version" do
      post "/Patient", params: valid_patient_payload, as: :json
      id = JSON.parse(response.body)["id"]

      put "/Patient/#{id}", params: valid_patient_payload(gender: "female"), headers: { "If-Match" => 'W/"1"' }, as: :json

      expect(response).to have_http_status(:ok)
    end

    it "returns 404 for an unknown id" do
      put "/Patient/does-not-exist", params: valid_patient_payload, as: :json

      expect(response).to have_http_status(:not_found)
    end

    it "returns 422 when the updated payload is invalid" do
      post "/Patient", params: valid_patient_payload, as: :json
      id = JSON.parse(response.body)["id"]

      put "/Patient/#{id}", params: valid_patient_payload(gender: "invalid"), as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "DELETE /Patient/:id" do
    it "deletes the patient and returns 204" do
      post "/Patient", params: valid_patient_payload, as: :json
      id = JSON.parse(response.body)["id"]

      delete "/Patient/#{id}"
      expect(response).to have_http_status(:no_content)

      get "/Patient/#{id}"
      expect(response).to have_http_status(:gone)
    end

    it "is idempotent when deleting an already-deleted patient" do
      post "/Patient", params: valid_patient_payload, as: :json
      id = JSON.parse(response.body)["id"]

      delete "/Patient/#{id}"
      delete "/Patient/#{id}"

      expect(response).to have_http_status(:no_content)
    end

    it "returns 404 for an unknown id" do
      delete "/Patient/does-not-exist"

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "history and vread" do
    it "returns full version history as a history Bundle" do
      post "/Patient", params: valid_patient_payload, as: :json
      id = JSON.parse(response.body)["id"]
      put "/Patient/#{id}", params: valid_patient_payload(gender: "female"), as: :json
      delete "/Patient/#{id}"

      get "/Patient/#{id}/_history"

      expect(response).to have_http_status(:ok)
      history = JSON.parse(response.body)
      expect(history["resourceType"]).to eq("Bundle")
      expect(history["type"]).to eq("history")
      expect(history["total"]).to eq(3)
    end

    it "returns a specific prior version via vread" do
      post "/Patient", params: valid_patient_payload, as: :json
      id = JSON.parse(response.body)["id"]
      put "/Patient/#{id}", params: valid_patient_payload(gender: "female"), as: :json

      get "/Patient/#{id}/_history/1"

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["gender"]).to eq("male")
    end

    it "returns 410 when reading a deleted version" do
      post "/Patient", params: valid_patient_payload, as: :json
      id = JSON.parse(response.body)["id"]
      delete "/Patient/#{id}"

      get "/Patient/#{id}/_history/2"

      expect(response).to have_http_status(:gone)
    end
  end

  describe "GET /Patient (search)" do
    it "finds a patient by identifier value" do
      payload = valid_patient_payload
      value = payload["identifier"].first["value"]
      post "/Patient", params: payload, as: :json

      get "/Patient", params: { identifier: value }

      expect(response).to have_http_status(:ok)
      bundle = JSON.parse(response.body)
      expect(bundle["resourceType"]).to eq("Bundle")
      expect(bundle["type"]).to eq("searchset")
      expect(bundle["total"]).to eq(1)
    end

    it "finds a patient by kana (SYL) name" do
      post "/Patient", params: valid_patient_payload, as: :json

      get "/Patient", params: { name: "ヤマダ" }

      bundle = JSON.parse(response.body)
      expect(bundle["total"]).to be >= 1
    end

    it "does not match a mid-string fragment by default (starts-with, not contains)" do
      post "/Patient", params: valid_patient_payload, as: :json

      get "/Patient", params: { family: "田" }

      bundle = JSON.parse(response.body)
      expect(bundle["total"]).to eq(0)
    end

    it "matches a mid-string fragment with the :contains modifier" do
      post "/Patient", params: valid_patient_payload, as: :json

      get "/Patient", params: { "family:contains": "田" }

      bundle = JSON.parse(response.body)
      expect(bundle["total"]).to be >= 1
    end

    it "filters by gender" do
      post "/Patient", params: valid_patient_payload(gender: "female"), as: :json

      get "/Patient", params: { gender: "female" }

      bundle = JSON.parse(response.body)
      expect(bundle["entry"]).to all(satisfy { |e| e["resource"]["gender"] == "female" })
    end

    it "excludes deleted patients from search results" do
      post "/Patient", params: valid_patient_payload, as: :json
      id = JSON.parse(response.body)["id"]
      delete "/Patient/#{id}"

      get "/Patient", params: { _id: id }

      bundle = JSON.parse(response.body)
      expect(bundle["total"]).to eq(0)
    end

    it "paginates with _count and _offset and exposes link relations" do
      3.times { post "/Patient", params: valid_patient_payload, as: :json }

      get "/Patient", params: { _count: 2, _offset: 0 }

      bundle = JSON.parse(response.body)
      expect(bundle["entry"].size).to eq(2)
      expect(bundle["link"].map { |l| l["relation"] }).to include("self", "next")
    end

    it "round-trips repeated parameters and modifiers through the next page link" do
      # Rails' `params:` hash serializes an Array value as `key[]=a&key[]=b`, which is
      # NOT how a real FHIR client repeats a parameter (`key=a&key=b`) -- so this uses a
      # literal query string to exercise the same wire format a real client sends.
      3.times { post "/Patient", params: valid_patient_payload, as: :json }

      get "/Patient?family:contains=#{CGI.escape('田')}&birthdate=ge1900-01-01&birthdate=le2100-01-01&_count=2&_offset=0"

      bundle = JSON.parse(response.body)
      expect(bundle["entry"].size).to eq(2)

      next_url = bundle["link"].find { |l| l["relation"] == "next" }["url"]
      expect(next_url).to include("family:contains=")
      expect(next_url.scan("birthdate=").size).to eq(2)
      expect(next_url).to include("_offset=2")

      get URI(next_url).request_uri

      next_bundle = JSON.parse(response.body)
      expect(next_bundle["entry"].size).to eq(1)
    end
  end
end
