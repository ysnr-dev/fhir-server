require "rails_helper"

RSpec.describe "OAuth token introspection (POST /oauth/introspect)", type: :request do
  let!(:registration) { OauthClient.register(name: "introspect-client", scopes: "system/*.read") }
  let(:client) { registration.first }
  let(:secret) { registration.last }

  def introspect(token, as: client, secret: self.secret, **extra)
    post "/oauth/introspect", params: { client_id: as.id, client_secret: secret, token: token, **extra }
    JSON.parse(response.body)
  end

  # A User belongs to a Patient row, so create the compartment root first.
  def register_launch_user(patient_id)
    Patient.create!(id: patient_id, content: { "resourceType" => "Patient" },
                    version_id: 1, last_updated: Time.current)
    register_user(patient_id: patient_id)
  end

  describe "an active token" do
    it "returns the token's metadata for a Backend Services token" do
      record, raw = AccessToken.issue(client, scopes: ["system/*.read"])

      body = introspect(raw)

      expect(response).to have_http_status(:ok)
      expect(response.headers["Cache-Control"]).to include("no-store")
      expect(body).to include(
        "active" => true,
        "scope" => "system/*.read",
        "client_id" => client.id,
        "token_type" => "bearer",
        "exp" => record.expires_at.to_i,
        "iat" => record.created_at.to_i,
        "aud" => "http://www.example.com",
        "iss" => "http://www.example.com"
      )
      # A machine token carries no user or patient context.
      expect(body).not_to have_key("sub")
      expect(body).not_to have_key("patient")
    end

    it "includes sub and the SMART patient context for a launch token" do
      launch_client, = OauthClient.register(
        name: "launch", scopes: "patient/*.read",
        redirect_uris: "https://app.example/cb", client_type: "public"
      )
      user = register_launch_user("patient-123")
      _record, raw = AccessToken.issue(launch_client, scopes: ["patient/*.read"], user: user, patient_id: "patient-123")

      body = introspect(raw)

      expect(body).to include(
        "active" => true,
        "sub" => user.id,
        "patient" => "patient-123",
        "scope" => "patient/*.read"
      )
    end

    it "introspects a token issued to another client (resource-server use case)" do
      other_client, = OauthClient.register(name: "other", scopes: "system/*.read")
      _record, raw = AccessToken.issue(other_client, scopes: ["system/*.read"])

      body = introspect(raw)

      expect(body).to include("active" => true, "client_id" => other_client.id)
    end

    it "reports an active refresh token without a token_type" do
      launch_client, = OauthClient.register(
        name: "refresh-launch", scopes: "patient/*.read offline_access",
        redirect_uris: "https://app.example/cb", client_type: "public"
      )
      user = register_launch_user("patient-9")
      code, = AuthorizationCode.issue(
        client: launch_client, user: user, scopes: %w[patient/*.read offline_access],
        redirect_uri: "https://app.example/cb", code_challenge: "c" * 43
      )
      _record, raw = RefreshToken.issue(
        client: launch_client, user: user, patient_id: user.patient_id,
        scopes: %w[patient/*.read offline_access], authorization_code: code
      )

      body = introspect(raw)

      expect(body).to include("active" => true, "sub" => user.id, "patient" => "patient-9")
      expect(body).not_to have_key("token_type")
    end
  end

  describe "an inactive token" do
    it "returns only active:false for an unknown token" do
      body = introspect("no-such-token")

      expect(response).to have_http_status(:ok)
      expect(body).to eq("active" => false)
    end

    it "returns active:false for a revoked token" do
      record, raw = AccessToken.issue(client, scopes: ["system/*.read"])
      record.update!(revoked_at: Time.current)

      expect(introspect(raw)).to eq("active" => false)
    end

    it "returns active:false for an expired token" do
      record, raw = AccessToken.issue(client, scopes: ["system/*.read"])
      record.update!(expires_at: 1.hour.ago)

      expect(introspect(raw)).to eq("active" => false)
    end

    it "returns active:false for a consumed (rotated) refresh token" do
      launch_client, = OauthClient.register(
        name: "rotated", scopes: "patient/*.read offline_access",
        redirect_uris: "https://app.example/cb", client_type: "public"
      )
      user = register_launch_user("patient-7")
      code, = AuthorizationCode.issue(
        client: launch_client, user: user, scopes: %w[patient/*.read offline_access],
        redirect_uri: "https://app.example/cb", code_challenge: "c" * 43
      )
      record, raw = RefreshToken.issue(
        client: launch_client, user: user, patient_id: user.patient_id,
        scopes: %w[patient/*.read offline_access], authorization_code: code
      )
      record.consume!

      expect(introspect(raw)).to eq("active" => false)
    end
  end

  describe "client authentication" do
    it "authenticates via HTTP Basic" do
      _record, raw = AccessToken.issue(client, scopes: ["system/*.read"])
      credentials = Base64.strict_encode64("#{client.id}:#{secret}")

      post "/oauth/introspect", params: { token: raw }, headers: { "Authorization" => "Basic #{credentials}" }

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to include("active" => true)
    end

    it "rejects bad client credentials with 401 invalid_client" do
      _record, raw = AccessToken.issue(client, scopes: ["system/*.read"])

      post "/oauth/introspect", params: { client_id: client.id, client_secret: "wrong", token: raw }

      expect(response).to have_http_status(:unauthorized)
      expect(JSON.parse(response.body)["error"]).to eq("invalid_client")
    end

    it "rejects an unauthenticated (public) client with 401 -- introspection requires authorization" do
      public_client, = OauthClient.register(
        name: "public-app", scopes: "patient/*.read",
        redirect_uris: "https://app.example/cb", client_type: "public"
      )
      _record, raw = AccessToken.issue(public_client, scopes: ["patient/*.read"], patient_id: "p1")

      post "/oauth/introspect", params: { client_id: public_client.id, token: raw }

      expect(response).to have_http_status(:unauthorized)
      expect(JSON.parse(response.body)["error"]).to eq("invalid_client")
    end
  end

  it "rejects a missing token parameter with 400 invalid_request" do
    post "/oauth/introspect", params: { client_id: client.id, client_secret: secret }

    expect(response).to have_http_status(:bad_request)
    expect(JSON.parse(response.body)["error"]).to eq("invalid_request")
  end

  it "advertises the introspection endpoint in the SMART configuration" do
    get "/.well-known/smart-configuration"

    expect(JSON.parse(response.body)["introspection_endpoint"]).to eq("http://www.example.com/oauth/introspect")
  end
end
