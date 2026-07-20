require "rails_helper"

RSpec.describe "PractitionerRoles", type: :request do
  describe "POST /PractitionerRole" do
    it "creates and returns 201 with Location header, ETag, and meta" do
      post "/PractitionerRole", params: valid_practitioner_role_payload, as: :json

      expect(response).to have_http_status(:created)
      expect(response.headers["Location"]).to match(%r{/PractitionerRole/[\w-]+/_history/1\z})
      expect(response.headers["ETag"]).to eq('W/"1"')

      body = JSON.parse(response.body)
      expect(body["resourceType"]).to eq("PractitionerRole")
    end

    it "returns 422 for a non-boolean active" do
      post "/PractitionerRole", params: valid_practitioner_role_payload(active: "yes"), as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "read, update, delete, history" do
    it "supports the full lifecycle" do
      post "/PractitionerRole", params: valid_practitioner_role_payload, as: :json
      id = JSON.parse(response.body)["id"]

      get "/PractitionerRole/#{id}"
      expect(response).to have_http_status(:ok)

      put "/PractitionerRole/#{id}", params: valid_practitioner_role_payload(active: false), as: :json
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["meta"]["versionId"]).to eq("2")

      delete "/PractitionerRole/#{id}"
      expect(response).to have_http_status(:no_content)

      get "/PractitionerRole/#{id}/_history"
      expect(JSON.parse(response.body)["total"]).to eq(3)
    end
  end

  describe "GET /PractitionerRole (search)" do
    it "finds by practitioner reference" do
      practitioner_id = SecureRandom.uuid
      post "/PractitionerRole",
           params: valid_practitioner_role_payload(practitioner: { "reference" => "Practitioner/#{practitioner_id}" }),
           as: :json

      get "/PractitionerRole", params: { practitioner: "Practitioner/#{practitioner_id}" }

      expect(JSON.parse(response.body)["total"]).to eq(1)
    end

    it "filters by specialty and active" do
      post "/PractitionerRole", params: valid_practitioner_role_payload, as: :json

      get "/PractitionerRole", params: { specialty: "394814009", active: "true" }

      bundle = JSON.parse(response.body)
      expect(bundle["type"]).to eq("searchset")
      expect(bundle["total"]).to be >= 1
    end
  end
end
