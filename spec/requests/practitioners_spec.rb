require "rails_helper"

RSpec.describe "Practitioners", type: :request do
  describe "POST /Practitioner" do
    it "creates and returns 201 with Location, ETag, and meta" do
      post "/Practitioner", params: valid_practitioner_payload, as: :json

      expect(response).to have_http_status(:created)
      expect(response.content_type).to include("application/fhir+json")
      expect(response.headers["Location"]).to match(%r{/Practitioner/[\w-]+/_history/1\z})
      expect(response.headers["ETag"]).to eq('W/"1"')

      body = JSON.parse(response.body)
      expect(body["resourceType"]).to eq("Practitioner")
      expect(body["meta"]["versionId"]).to eq("1")
    end

    it "succeeds with an entirely empty resource (JP Core: nothing is truly required)" do
      post "/Practitioner", params: { "resourceType" => "Practitioner" }, as: :json

      expect(response).to have_http_status(:created)
    end

    it "returns 422 for an invalid gender" do
      post "/Practitioner", params: valid_practitioner_payload(gender: "invalid"), as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "returns 400 when resourceType does not match" do
      post "/Practitioner", params: valid_practitioner_payload.merge("resourceType" => "Patient"), as: :json

      expect(response).to have_http_status(:bad_request)
    end
  end

  describe "GET /Practitioner/:id" do
    it "returns the resource" do
      post "/Practitioner", params: valid_practitioner_payload, as: :json
      id = JSON.parse(response.body)["id"]

      get "/Practitioner/#{id}"

      expect(response).to have_http_status(:ok)
      expect(response.headers["ETag"]).to eq('W/"1"')
    end

    it "returns 404 for an unknown id" do
      get "/Practitioner/does-not-exist"

      expect(response).to have_http_status(:not_found)
    end

    it "returns 410 for a deleted resource" do
      post "/Practitioner", params: valid_practitioner_payload, as: :json
      id = JSON.parse(response.body)["id"]
      delete "/Practitioner/#{id}"

      get "/Practitioner/#{id}"

      expect(response).to have_http_status(:gone)
    end
  end

  describe "PUT /Practitioner/:id" do
    it "updates the resource and increments the version" do
      post "/Practitioner", params: valid_practitioner_payload, as: :json
      id = JSON.parse(response.body)["id"]

      put "/Practitioner/#{id}", params: valid_practitioner_payload(gender: "female"), as: :json

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["gender"]).to eq("female")
      expect(body["meta"]["versionId"]).to eq("2")
    end

    it "returns 412 when If-Match does not match the current version" do
      post "/Practitioner", params: valid_practitioner_payload, as: :json
      id = JSON.parse(response.body)["id"]

      put "/Practitioner/#{id}", params: valid_practitioner_payload, headers: { "If-Match" => 'W/"99"' }, as: :json

      expect(response).to have_http_status(:precondition_failed)
    end
  end

  describe "DELETE /Practitioner/:id" do
    it "deletes the resource and returns 204" do
      post "/Practitioner", params: valid_practitioner_payload, as: :json
      id = JSON.parse(response.body)["id"]

      delete "/Practitioner/#{id}"
      expect(response).to have_http_status(:no_content)

      get "/Practitioner/#{id}"
      expect(response).to have_http_status(:gone)
    end
  end

  describe "history and vread" do
    it "returns full version history and a specific version" do
      post "/Practitioner", params: valid_practitioner_payload, as: :json
      id = JSON.parse(response.body)["id"]
      put "/Practitioner/#{id}", params: valid_practitioner_payload(gender: "female"), as: :json

      get "/Practitioner/#{id}/_history"
      history = JSON.parse(response.body)
      expect(history["type"]).to eq("history")
      expect(history["total"]).to eq(2)

      get "/Practitioner/#{id}/_history/1"
      expect(JSON.parse(response.body)["gender"]).to eq("male")
    end
  end

  describe "GET /Practitioner (search)" do
    it "finds a practitioner by kana (SYL) name" do
      post "/Practitioner", params: valid_practitioner_payload, as: :json

      get "/Practitioner", params: { name: "スズキ" }

      bundle = JSON.parse(response.body)
      expect(bundle["type"]).to eq("searchset")
      expect(bundle["total"]).to be >= 1
    end

    it "filters by gender" do
      post "/Practitioner", params: valid_practitioner_payload(gender: "female"), as: :json

      get "/Practitioner", params: { gender: "female" }

      bundle = JSON.parse(response.body)
      expect(bundle["entry"]).to all(satisfy { |e| e["resource"]["gender"] == "female" })
    end

    it "excludes deleted practitioners from search results" do
      post "/Practitioner", params: valid_practitioner_payload, as: :json
      id = JSON.parse(response.body)["id"]
      delete "/Practitioner/#{id}"

      get "/Practitioner", params: { _id: id }

      expect(JSON.parse(response.body)["total"]).to eq(0)
    end
  end
end
