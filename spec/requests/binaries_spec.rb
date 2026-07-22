require "rails_helper"

RSpec.describe "Binary", type: :request do
  describe "create" do
    it "creates a valid binary with 201" do
      post "/Binary", params: valid_binary_payload, as: :json

      expect(response).to have_http_status(:created)
      expect(JSON.parse(response.body)["contentType"]).to eq("text/plain")
    end

    it "returns 422 when contentType is missing" do
      post "/Binary", params: valid_binary_payload.except("contentType"), as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "returns 422 when data is not valid base64" do
      post "/Binary", params: valid_binary_payload(data: "not base64!!"), as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)["issue"].first["expression"]).to include("Binary.data")
    end
  end

  describe "read" do
    it "returns the JSON representation by default" do
      post "/Binary", params: valid_binary_payload, as: :json
      binary_id = JSON.parse(response.body)["id"]

      get "/Binary/#{binary_id}"

      expect(response.content_type).to start_with("application/fhir+json")
      body = JSON.parse(response.body)
      expect(body["resourceType"]).to eq("Binary")
      expect(Base64.strict_decode64(body["data"])).to eq("診療情報テキスト".b)
    end

    it "returns the raw decoded content for a non-FHIR Accept header" do
      post "/Binary", params: valid_binary_payload, as: :json
      binary_id = JSON.parse(response.body)["id"]

      get "/Binary/#{binary_id}", headers: { "Accept" => "text/plain" }

      expect(response).to have_http_status(:ok)
      expect(response.content_type).to start_with("text/plain")
      expect(response.headers["ETag"]).to eq(%(W/"1"))
      expect(response.body).to eq("診療情報テキスト".b)
    end

    it "keeps returning JSON for explicit fhir+json and wildcard Accept" do
      post "/Binary", params: valid_binary_payload, as: :json
      binary_id = JSON.parse(response.body)["id"]

      get "/Binary/#{binary_id}", headers: { "Accept" => "application/fhir+json" }
      expect(JSON.parse(response.body)["resourceType"]).to eq("Binary")

      get "/Binary/#{binary_id}", headers: { "Accept" => "*/*" }
      expect(JSON.parse(response.body)["resourceType"]).to eq("Binary")
    end
  end

  it "supports versioning like any other resource" do
    post "/Binary", params: valid_binary_payload, as: :json
    binary_id = JSON.parse(response.body)["id"]

    put "/Binary/#{binary_id}", params: valid_binary_payload(data: Base64.strict_encode64("updated")), as: :json
    expect(JSON.parse(response.body)["meta"]["versionId"]).to eq("2")

    get "/Binary/#{binary_id}/_history"
    expect(JSON.parse(response.body)["total"]).to eq(2)
  end
end
