require "rails_helper"

RSpec.describe "Medications", type: :request do
  describe "POST /Medication" do
    it "creates and returns 201 with Location, ETag, and meta" do
      post "/Medication", params: valid_medication_payload, as: :json

      expect(response).to have_http_status(:created)
      expect(response.content_type).to include("application/fhir+json")
      expect(response.headers["Location"]).to match(%r{/Medication/[\w-]+/_history/1\z})
      expect(response.headers["ETag"]).to eq('W/"1"')

      body = JSON.parse(response.body)
      expect(body["resourceType"]).to eq("Medication")
      expect(body["meta"]["versionId"]).to eq("1")
      expect(body["meta"]["profile"]).to eq(["http://jpfhir.jp/fhir/core/StructureDefinition/JP_Medication"])
    end

    it "returns 422 for an invalid status" do
      post "/Medication", params: valid_medication_payload(status: "bogus"), as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "returns 422 when code is missing" do
      post "/Medication", params: valid_medication_payload.except("code"), as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "returns 400 when resourceType does not match" do
      post "/Medication", params: valid_medication_payload.merge("resourceType" => "Patient"), as: :json

      expect(response).to have_http_status(:bad_request)
    end
  end

  describe "GET /Medication/:id" do
    it "returns the resource" do
      post "/Medication", params: valid_medication_payload, as: :json
      id = JSON.parse(response.body)["id"]

      get "/Medication/#{id}"

      expect(response).to have_http_status(:ok)
      expect(response.headers["ETag"]).to eq('W/"1"')
    end

    it "returns 404 for an unknown id" do
      get "/Medication/does-not-exist"

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "PUT /Medication/:id" do
    it "updates the resource and increments the version" do
      post "/Medication", params: valid_medication_payload, as: :json
      id = JSON.parse(response.body)["id"]

      put "/Medication/#{id}", params: valid_medication_payload(status: "inactive"), as: :json

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["status"]).to eq("inactive")
      expect(body["meta"]["versionId"]).to eq("2")
    end
  end

  describe "DELETE /Medication/:id" do
    it "deletes the resource and returns 204" do
      post "/Medication", params: valid_medication_payload, as: :json
      id = JSON.parse(response.body)["id"]

      delete "/Medication/#{id}"
      expect(response).to have_http_status(:no_content)

      get "/Medication/#{id}"
      expect(response).to have_http_status(:gone)
    end
  end

  describe "GET /Medication (search)" do
    it "finds by status" do
      post "/Medication", params: valid_medication_payload(status: "inactive"), as: :json

      get "/Medication", params: { status: "inactive" }

      bundle = JSON.parse(response.body)
      expect(bundle["type"]).to eq("searchset")
      expect(bundle["total"]).to be >= 1
    end

    it "finds by code" do
      post "/Medication", params: valid_medication_payload, as: :json

      get "/Medication", params: { code: "620004422" }

      bundle = JSON.parse(response.body)
      expect(bundle["total"]).to be >= 1
    end

    it "excludes deleted resources from search results" do
      post "/Medication", params: valid_medication_payload, as: :json
      id = JSON.parse(response.body)["id"]
      delete "/Medication/#{id}"

      get "/Medication", params: { _id: id }

      expect(JSON.parse(response.body)["total"]).to eq(0)
    end
  end
end
