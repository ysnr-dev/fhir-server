require "rails_helper"

RSpec.describe "Conditional read (If-None-Match / If-Modified-Since)", type: :request do
  def create_patient
    post "/Patient", params: valid_patient_payload, as: :json
    JSON.parse(response.body)["id"]
  end

  describe "If-None-Match" do
    it "returns 304 with the ETag and no body when the version matches" do
      id = create_patient

      get "/Patient/#{id}", headers: { "If-None-Match" => %(W/"1") }

      expect(response).to have_http_status(:not_modified)
      expect(response.headers["ETag"]).to eq(%(W/"1"))
      expect(response.body).to be_empty
    end

    it "returns 200 with the resource when the version differs" do
      id = create_patient
      put "/Patient/#{id}", params: valid_patient_payload("gender" => "female"), as: :json

      get "/Patient/#{id}", headers: { "If-None-Match" => %(W/"1") }

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["meta"]["versionId"]).to eq("2")
    end

    it "treats * as matching any existing version" do
      id = create_patient

      get "/Patient/#{id}", headers: { "If-None-Match" => "*" }

      expect(response).to have_http_status(:not_modified)
    end

    it "accepts an unquoted strong ETag form" do
      id = create_patient

      get "/Patient/#{id}", headers: { "If-None-Match" => '"1"' }

      expect(response).to have_http_status(:not_modified)
    end

    it "still returns 404/410 for missing or deleted resources" do
      get "/Patient/no-such-id", headers: { "If-None-Match" => %(W/"1") }
      expect(response).to have_http_status(:not_found)

      id = create_patient
      delete "/Patient/#{id}"
      get "/Patient/#{id}", headers: { "If-None-Match" => %(W/"1") }
      expect(response).to have_http_status(:gone)
    end
  end

  describe "If-Modified-Since" do
    it "returns 304 when the resource has not changed since the given time" do
      id = create_patient

      get "/Patient/#{id}", headers: { "If-Modified-Since" => 1.hour.from_now.httpdate }

      expect(response).to have_http_status(:not_modified)
    end

    it "returns 200 when the resource changed after the given time" do
      id = create_patient

      get "/Patient/#{id}", headers: { "If-Modified-Since" => 1.hour.ago.httpdate }

      expect(response).to have_http_status(:ok)
    end

    it "ignores an unparseable date and returns 200" do
      id = create_patient

      get "/Patient/#{id}", headers: { "If-Modified-Since" => "not-a-date" }

      expect(response).to have_http_status(:ok)
    end

    it "yields to If-None-Match when both are present" do
      id = create_patient
      put "/Patient/#{id}", params: valid_patient_payload("gender" => "female"), as: :json

      # If-Modified-Since alone would 304, but the mismatched ETag wins -> 200.
      get "/Patient/#{id}", headers: { "If-None-Match" => %(W/"1"),
                                       "If-Modified-Since" => 1.hour.from_now.httpdate }

      expect(response).to have_http_status(:ok)
    end
  end
end
