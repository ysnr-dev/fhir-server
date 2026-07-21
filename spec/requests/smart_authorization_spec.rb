require "rails_helper"

RSpec.describe "SMART Backend Services enforcement", type: :request do
  it "leaves all endpoints open while auth is disabled (the default)" do
    get "/Patient"

    expect(response).to have_http_status(:ok)
  end

  describe "with auth enabled" do
    around { |example| with_fhir_auth { example.run } }

    it "returns 401 with a bare challenge when no token is presented" do
      get "/Patient"

      expect(response).to have_http_status(:unauthorized)
      expect(response.headers["WWW-Authenticate"]).to eq(%(Bearer realm="fhir-server"))
      expect(JSON.parse(response.body)["issue"].first["code"]).to eq("login")
    end

    it "returns 401 invalid_token for an unknown token" do
      get "/Patient", headers: bearer_header("no-such-token")

      expect(response).to have_http_status(:unauthorized)
      expect(response.headers["WWW-Authenticate"]).to include('error="invalid_token"')
    end

    it "returns 401 for an expired token" do
      token = issue_access_token
      AccessToken.update_all(expires_at: 1.minute.ago)

      get "/Patient", headers: bearer_header(token)

      expect(response).to have_http_status(:unauthorized)
      expect(JSON.parse(response.body)["issue"].first["code"]).to eq("expired")
    end

    it "allows reads and blocks writes with a read-only scope" do
      token = issue_access_token(scopes: "system/*.read")

      get "/Patient", headers: bearer_header(token)
      expect(response).to have_http_status(:ok)

      post "/Patient", params: valid_patient_payload.to_json,
                       headers: bearer_header(token).merge("CONTENT_TYPE" => "application/json")
      expect(response).to have_http_status(:forbidden)
      expect(JSON.parse(response.body)["issue"].first["diagnostics"]).to include("system/Patient.write")
    end

    it "scopes access per resource type" do
      token = issue_access_token(scopes: "system/Patient.read")

      get "/Patient", headers: bearer_header(token)
      expect(response).to have_http_status(:ok)

      get "/Observation", headers: bearer_header(token)
      expect(response).to have_http_status(:forbidden)
    end

    it "grants everything with system/*.*" do
      token = issue_access_token(scopes: "system/*.*")

      post "/Patient", params: valid_patient_payload.to_json,
                       headers: bearer_header(token).merge("CONTENT_TYPE" => "application/json")
      expect(response).to have_http_status(:created)

      get "/_history", headers: bearer_header(token)
      expect(response).to have_http_status(:ok)
    end

    it "requires a wildcard-type read grant for system-level history" do
      token = issue_access_token(scopes: "system/Patient.read")

      get "/_history", headers: bearer_header(token)

      expect(response).to have_http_status(:forbidden)
    end

    it "checks every entry of a Bundle against the token's scopes" do
      token = issue_access_token(scopes: "system/Patient.write system/Patient.read")
      bundle = {
        "resourceType" => "Bundle",
        "type" => "transaction",
        "entry" => [
          { "resource" => valid_patient_payload, "request" => { "method" => "POST", "url" => "Patient" } },
          { "request" => { "method" => "GET", "url" => "Observation?status=final" } }
        ]
      }

      post "/", params: bundle.to_json, headers: bearer_header(token).merge("CONTENT_TYPE" => "application/json")

      expect(response).to have_http_status(:forbidden)
      expect(JSON.parse(response.body)["issue"].first["diagnostics"]).to include("system/Observation.read")
      expect(Patient.count).to eq(0)

      bundle["entry"].pop
      post "/", params: bundle.to_json, headers: bearer_header(token).merge("CONTENT_TYPE" => "application/json")
      expect(response).to have_http_status(:ok)
    end

    it "keeps /metadata, /.well-known/smart-configuration, and /oauth/token public" do
      get "/metadata"
      expect(response).to have_http_status(:ok)

      get "/.well-known/smart-configuration"
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["grant_types_supported"]).to eq(["client_credentials"])
      expect(JSON.parse(response.body)["token_endpoint"]).to end_with("/oauth/token")

      client, secret = OauthClient.register(name: "pub", scopes: "system/*.read")
      post "/oauth/token", params: { grant_type: "client_credentials", client_id: client.id, client_secret: secret }
      expect(response).to have_http_status(:ok)
    end

    it "advertises SMART security in the CapabilityStatement" do
      get "/metadata"

      security = JSON.parse(response.body)["rest"].first["security"]
      expect(security.dig("service", 0, "coding", 0, "code")).to eq("SMART-on-FHIR")
      token_uri = security["extension"].first["extension"].first
      expect(token_uri["url"]).to eq("token")
      expect(token_uri["valueUri"]).to end_with("/oauth/token")
    end

    it "authorizes an end-to-end token flow: register -> token -> API call" do
      client, secret = OauthClient.register(name: "e2e", scopes: "system/*.read system/*.write")
      post "/oauth/token", params: { grant_type: "client_credentials", client_id: client.id, client_secret: secret }
      token = JSON.parse(response.body)["access_token"]

      post "/Patient", params: valid_patient_payload.to_json,
                       headers: bearer_header(token).merge("CONTENT_TYPE" => "application/json")
      expect(response).to have_http_status(:created)

      patient_id = JSON.parse(response.body)["id"]
      get "/Patient/#{patient_id}/$everything", headers: bearer_header(token)
      expect(response).to have_http_status(:ok)
    end
  end
end
