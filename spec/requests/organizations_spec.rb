require "rails_helper"

RSpec.describe "Organizations", type: :request do
  describe "POST /Organization" do
    it "creates and returns 201 with Location, ETag, and meta" do
      post "/Organization", params: valid_organization_payload, as: :json

      expect(response).to have_http_status(:created)
      expect(response.content_type).to include("application/fhir+json")
      expect(response.headers["Location"]).to match(%r{/Organization/[\w-]+/_history/1\z})
      expect(response.headers["ETag"]).to eq('W/"1"')

      body = JSON.parse(response.body)
      expect(body["resourceType"]).to eq("Organization")
      expect(body["meta"]["versionId"]).to eq("1")
    end

    it "succeeds with only identifier present (org-1)" do
      post "/Organization", params: valid_organization_payload.except("name"), as: :json

      expect(response).to have_http_status(:created)
    end

    it "succeeds with only name present (org-1)" do
      post "/Organization", params: valid_organization_payload.except("identifier"), as: :json

      expect(response).to have_http_status(:created)
    end

    it "returns 422 when both identifier and name are absent (org-1)" do
      post "/Organization", params: valid_organization_payload.except("identifier", "name"), as: :json

      expect(response).to have_http_status(:unprocessable_content)
      body = JSON.parse(response.body)
      expect(body["issue"].first["code"]).to eq("invariant")
    end

    it "returns 400 when resourceType does not match" do
      post "/Organization", params: valid_organization_payload.merge("resourceType" => "Patient"), as: :json

      expect(response).to have_http_status(:bad_request)
    end
  end

  describe "GET /Organization/:id" do
    it "returns the resource" do
      post "/Organization", params: valid_organization_payload, as: :json
      id = JSON.parse(response.body)["id"]

      get "/Organization/#{id}"

      expect(response).to have_http_status(:ok)
      expect(response.headers["ETag"]).to eq('W/"1"')
    end

    it "returns 404 for an unknown id" do
      get "/Organization/does-not-exist"

      expect(response).to have_http_status(:not_found)
    end

    it "returns 410 for a deleted resource" do
      post "/Organization", params: valid_organization_payload, as: :json
      id = JSON.parse(response.body)["id"]
      delete "/Organization/#{id}"

      get "/Organization/#{id}"

      expect(response).to have_http_status(:gone)
    end
  end

  describe "PUT /Organization/:id" do
    it "updates the resource and increments the version" do
      post "/Organization", params: valid_organization_payload, as: :json
      id = JSON.parse(response.body)["id"]

      put "/Organization/#{id}", params: valid_organization_payload(name: "別の病院"), as: :json

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["name"]).to eq("別の病院")
      expect(body["meta"]["versionId"]).to eq("2")
    end

    it "returns 412 when If-Match does not match the current version" do
      post "/Organization", params: valid_organization_payload, as: :json
      id = JSON.parse(response.body)["id"]

      put "/Organization/#{id}", params: valid_organization_payload, headers: { "If-Match" => 'W/"99"' }, as: :json

      expect(response).to have_http_status(:precondition_failed)
    end
  end

  describe "DELETE /Organization/:id" do
    it "deletes the resource and returns 204" do
      post "/Organization", params: valid_organization_payload, as: :json
      id = JSON.parse(response.body)["id"]

      delete "/Organization/#{id}"
      expect(response).to have_http_status(:no_content)

      get "/Organization/#{id}"
      expect(response).to have_http_status(:gone)
    end
  end

  describe "history and vread" do
    it "returns full version history and a specific version" do
      post "/Organization", params: valid_organization_payload, as: :json
      id = JSON.parse(response.body)["id"]
      put "/Organization/#{id}", params: valid_organization_payload(name: "別の病院"), as: :json

      get "/Organization/#{id}/_history"
      history = JSON.parse(response.body)
      expect(history["type"]).to eq("history")
      expect(history["total"]).to eq(2)

      get "/Organization/#{id}/_history/1"
      expect(JSON.parse(response.body)["name"]).to eq("サンプル病院")
    end
  end

  describe "GET /Organization (search)" do
    it "finds by name" do
      post "/Organization", params: valid_organization_payload, as: :json

      get "/Organization", params: { name: "サンプル" }

      bundle = JSON.parse(response.body)
      expect(bundle["type"]).to eq("searchset")
      expect(bundle["total"]).to be >= 1
    end

    it "filters by active" do
      post "/Organization", params: valid_organization_payload(active: false), as: :json

      get "/Organization", params: { active: "false" }

      bundle = JSON.parse(response.body)
      expect(bundle["entry"]).to all(satisfy { |e| e["resource"]["active"] == false })
    end

    it "excludes deleted organizations from search results" do
      post "/Organization", params: valid_organization_payload, as: :json
      id = JSON.parse(response.body)["id"]
      delete "/Organization/#{id}"

      get "/Organization", params: { _id: id }

      expect(JSON.parse(response.body)["total"]).to eq(0)
    end
  end
end
