require "rails_helper"

RSpec.describe "Locations", type: :request do
  describe "POST /Location" do
    it "creates and returns 201 with Location header, ETag, and meta" do
      post "/Location", params: valid_location_payload, as: :json

      expect(response).to have_http_status(:created)
      expect(response.content_type).to include("application/fhir+json")
      expect(response.headers["Location"]).to match(%r{/Location/[\w-]+/_history/1\z})
      expect(response.headers["ETag"]).to eq('W/"1"')

      body = JSON.parse(response.body)
      expect(body["resourceType"]).to eq("Location")
      expect(body["meta"]["versionId"]).to eq("1")
    end

    it "returns 422 for an invalid status" do
      post "/Location", params: valid_location_payload(status: "bogus"), as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "returns 400 when resourceType does not match" do
      post "/Location", params: valid_location_payload.merge("resourceType" => "Patient"), as: :json

      expect(response).to have_http_status(:bad_request)
    end
  end

  describe "read, update, delete, history" do
    it "supports the full lifecycle" do
      post "/Location", params: valid_location_payload, as: :json
      id = JSON.parse(response.body)["id"]

      get "/Location/#{id}"
      expect(response).to have_http_status(:ok)

      put "/Location/#{id}", params: valid_location_payload(name: "第2診察室"), as: :json
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["meta"]["versionId"]).to eq("2")

      delete "/Location/#{id}"
      expect(response).to have_http_status(:no_content)

      get "/Location/#{id}"
      expect(response).to have_http_status(:gone)

      get "/Location/#{id}/_history"
      expect(JSON.parse(response.body)["total"]).to eq(3)
    end
  end

  describe "GET /Location (search)" do
    it "finds by name" do
      post "/Location", params: valid_location_payload(name: "救急外来"), as: :json

      get "/Location", params: { name: "救急" }

      bundle = JSON.parse(response.body)
      expect(bundle["type"]).to eq("searchset")
      expect(bundle["total"]).to be >= 1
    end

    it "does not match a mid-string fragment by default (starts-with, not contains)" do
      post "/Location", params: valid_location_payload(name: "救急外来"), as: :json

      get "/Location", params: { name: "外来" }

      bundle = JSON.parse(response.body)
      expect(bundle["total"]).to eq(0)
    end

    it "matches a mid-string fragment with the :contains modifier" do
      post "/Location", params: valid_location_payload(name: "救急外来"), as: :json

      get "/Location", params: { "name:contains": "外来" }

      bundle = JSON.parse(response.body)
      expect(bundle["total"]).to be >= 1
    end

    it "filters by status" do
      post "/Location", params: valid_location_payload(status: "inactive"), as: :json

      get "/Location", params: { status: "inactive" }

      bundle = JSON.parse(response.body)
      expect(bundle["entry"]).to all(satisfy { |e| e["resource"]["status"] == "inactive" })
    end

    it "filters by managing organization reference" do
      org_id = SecureRandom.uuid
      post "/Location",
           params: valid_location_payload(managingOrganization: { "reference" => "Organization/#{org_id}" }),
           as: :json

      get "/Location", params: { organization: "Organization/#{org_id}" }

      expect(JSON.parse(response.body)["total"]).to eq(1)
    end
  end
end
