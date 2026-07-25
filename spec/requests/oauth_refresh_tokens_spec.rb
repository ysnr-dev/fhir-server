require "rails_helper"

# The refresh side of the interactive launch: offline_access / online_access
# consented at authorization -> refresh_token issued at the token endpoint ->
# rotation via grant_type=refresh_token, with replay revoking the whole grant.
RSpec.describe "OAuth refresh tokens", type: :request do
  around { |example| with_fhir_auth { example.run } }

  let(:system_token) { issue_access_token(scopes: "system/*.*") }
  let(:redirect_uri) { "https://app.example/cb" }
  let(:verifier) { "a" * 64 }
  let(:challenge) { Base64.urlsafe_encode64(OpenSSL::Digest::SHA256.digest(verifier), padding: false) }
  let(:password) { "correct-horse-battery" }
  let(:scope) { "patient/*.read offline_access" }

  let!(:patient_id) do
    post "/Patient", params: valid_patient_payload.to_json,
                     headers: bearer_header(system_token).merge("CONTENT_TYPE" => "application/json")
    JSON.parse(response.body)["id"]
  end
  let!(:user) { register_user(patient_id: patient_id, email: "p@example.com", password: password) }

  let(:client) do
    OauthClient.register(
      name: "My Health App", scopes: "patient/*.read offline_access online_access",
      redirect_uris: redirect_uri, client_type: "public"
    ).first
  end

  def authorize_params(**overrides)
    {
      response_type: "code", client_id: client.id, redirect_uri: redirect_uri,
      scope: scope, state: "xyz-state",
      code_challenge: challenge, code_challenge_method: "S256"
    }.merge(overrides)
  end

  def obtain_code(**overrides)
    post "/oauth/login", params: authorize_params(**overrides).merge(email: user.email, password: password)
    expect(response).to have_http_status(:ok)

    post "/oauth/consent", params: authorize_params(**overrides).merge(decision: "approve")
    expect(response).to have_http_status(:found)
    Rack::Utils.parse_query(URI.parse(response.headers["Location"]).query)["code"]
  end

  # Runs the whole browser + code exchange and returns the parsed token body.
  def obtain_tokens(exchange: {}, **overrides)
    post "/oauth/token", params: {
      grant_type: "authorization_code", code: obtain_code(**overrides), redirect_uri: redirect_uri,
      client_id: client.id, code_verifier: verifier
    }.merge(exchange)
    expect(response).to have_http_status(:ok)
    JSON.parse(response.body)
  end

  def refresh(token, **overrides)
    post "/oauth/token", params: {
      grant_type: "refresh_token", refresh_token: token, client_id: client.id
    }.merge(overrides)
  end

  describe "issuance at the code exchange" do
    it "returns a refresh token when offline_access was consented" do
      body = obtain_tokens

      expect(body["refresh_token"]).to be_present
      expect(body["scope"]).to eq(scope)
      expect(RefreshToken.count).to eq(1)
      expect(RefreshToken.sole.expires_at).to be_within(1.minute).of(RefreshToken::OFFLINE_TTL.from_now)
    end

    it "returns a short-lived refresh token for online_access" do
      obtain_tokens(scope: "patient/*.read online_access")

      expect(RefreshToken.sole.expires_at).to be_within(1.minute).of(RefreshToken::ONLINE_TTL.from_now)
    end

    it "returns no refresh token without a context scope" do
      body = obtain_tokens(scope: "patient/*.read")

      expect(body).not_to have_key("refresh_token")
      expect(RefreshToken.count).to eq(0)
    end

    it "never returns a refresh token for client_credentials" do
      backend, secret = OauthClient.register(name: "backend", scopes: "system/*.read")

      post "/oauth/token", params: { grant_type: "client_credentials", client_id: backend.id, client_secret: secret }

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).not_to have_key("refresh_token")
    end
  end

  describe "grant_type=refresh_token" do
    it "rotates: issues a fresh access token and refresh token, consuming the old one" do
      body = obtain_tokens

      refresh(body["refresh_token"])

      expect(response).to have_http_status(:ok)
      rotated = JSON.parse(response.body)
      expect(rotated["access_token"]).not_to eq(body["access_token"])
      expect(rotated["refresh_token"]).not_to eq(body["refresh_token"])
      expect(rotated["scope"]).to eq(scope)
      expect(rotated["patient"]).to eq(patient_id)

      # The new access token works, confined to the same compartment.
      get "/Patient/#{patient_id}", headers: bearer_header(rotated["access_token"])
      expect(response).to have_http_status(:ok)
    end

    # Narrowing is a literal subset of the granted scope strings, matching how
    # scope requests are checked against the registration elsewhere.
    it "narrows the access token to a requested scope subset" do
      body = obtain_tokens

      refresh(body["refresh_token"], scope: "patient/*.read")

      rotated = JSON.parse(response.body)
      expect(rotated["scope"]).to eq("patient/*.read")
      # The grant itself keeps the original scopes: the rotated refresh token
      # still carries offline_access.
      refresh(rotated["refresh_token"])
      expect(JSON.parse(response.body)["scope"]).to eq(scope)
    end

    it "rejects a scope beyond the original grant" do
      body = obtain_tokens

      refresh(body["refresh_token"], scope: "system/*.read")

      expect(response).to have_http_status(:bad_request)
      expect(JSON.parse(response.body)["error"]).to eq("invalid_scope")
    end

    it "rejects an unknown refresh token" do
      refresh("nope")

      expect(response).to have_http_status(:bad_request)
      expect(JSON.parse(response.body)["error"]).to eq("invalid_grant")
    end

    it "rejects an expired refresh token" do
      body = obtain_tokens
      RefreshToken.update_all(expires_at: 1.minute.ago)

      refresh(body["refresh_token"])

      expect(JSON.parse(response.body)["error"]).to eq("invalid_grant")
    end

    it "rejects a public client presenting someone else's client_id" do
      body = obtain_tokens
      other, = OauthClient.register(name: "other", scopes: "patient/*.read",
                                    redirect_uris: redirect_uri, client_type: "public")

      refresh(body["refresh_token"], client_id: other.id)

      expect(response).to have_http_status(:unauthorized)
      expect(JSON.parse(response.body)["error"]).to eq("invalid_client")
    end

    # A replayed (already rotated-out) refresh token means it leaked, and the
    # legitimate client holds the replacement -- revoke the whole grant.
    it "revokes the entire grant when a rotated-out refresh token is replayed" do
      body = obtain_tokens
      refresh(body["refresh_token"])
      rotated = JSON.parse(response.body)

      refresh(body["refresh_token"])

      expect(response).to have_http_status(:bad_request)
      expect(JSON.parse(response.body)["error"]).to eq("invalid_grant")

      # Both the rotated refresh token and every access token are dead.
      get "/Patient/#{patient_id}", headers: bearer_header(rotated["access_token"])
      expect(response).to have_http_status(:unauthorized)
      refresh(rotated["refresh_token"])
      expect(JSON.parse(response.body)["error"]).to eq("invalid_grant")
    end

    it "authenticates a confidential client with its secret" do
      confidential, secret = OauthClient.register(
        name: "server-side app", scopes: "patient/*.read offline_access",
        redirect_uris: redirect_uri, client_type: "confidential"
      )
      body = obtain_tokens(client_id: confidential.id,
                           exchange: { client_id: confidential.id, client_secret: secret })

      refresh(body["refresh_token"], client_id: confidential.id, client_secret: secret)
      expect(response).to have_http_status(:ok)

      # And rejects the same request without credentials.
      rotated = JSON.parse(response.body)
      refresh(rotated["refresh_token"], client_id: confidential.id)
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "revocation (POST /oauth/revoke)" do
    it "revoking a refresh token ends the whole grant" do
      body = obtain_tokens

      post "/oauth/revoke", params: { token: body["refresh_token"], client_id: client.id }
      expect(response).to have_http_status(:ok)

      refresh(body["refresh_token"])
      expect(JSON.parse(response.body)["error"]).to eq("invalid_grant")
      get "/Patient/#{patient_id}", headers: bearer_header(body["access_token"])
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "authorization request validation" do
    it "rejects offline_access without any patient/ resource scope" do
      post "/oauth/login", params: authorize_params(scope: "offline_access")
                             .merge(email: user.email, password: password)

      expect(response).to have_http_status(:found)
      query = Rack::Utils.parse_query(URI.parse(response.headers["Location"]).query)
      expect(query["error"]).to eq("invalid_scope")
    end

    it "rejects a context scope the client did not register" do
      bare, = OauthClient.register(name: "bare", scopes: "patient/*.read",
                                   redirect_uris: redirect_uri, client_type: "public")

      post "/oauth/login", params: authorize_params(client_id: bare.id)
                             .merge(email: user.email, password: password)

      expect(response).to have_http_status(:found)
      query = Rack::Utils.parse_query(URI.parse(response.headers["Location"]).query)
      expect(query["error"]).to eq("invalid_scope")
    end

    it "explains the context scope on the consent screen" do
      post "/oauth/login", params: authorize_params.merge(email: user.email, password: password)

      expect(response.body).to include("再ログインなしでアクセスを継続")
    end
  end

  describe "when the owning client has been deleted" do
    # かつて refresh_tokens には oauth_clients へのFKも has_many もなく、
    # クライアント削除でトークンだけが「所有者 nil のまま有効」で生き残っていた。
    # その状態で refresh すると authenticate_owning_client(nil) が
    # nil.public_client? を呼び、invalid_grant ではなく 500 になっていた。
    it "returns invalid_grant instead of 500" do
      tokens = obtain_tokens
      raw_refresh = tokens["refresh_token"]
      client_id = client.id

      expect { client.destroy! }.to change(RefreshToken, :count).by(-1)

      post "/oauth/token", params: {
        grant_type: "refresh_token", refresh_token: raw_refresh, client_id: client_id
      }

      expect(response).to have_http_status(:bad_request)
      expect(JSON.parse(response.body)["error"]).to eq("invalid_grant")
    end
  end

  describe "discovery" do
    it "advertises refresh_token support" do
      get "/.well-known/smart-configuration"

      body = JSON.parse(response.body)
      expect(body["grant_types_supported"]).to include("refresh_token")
      expect(body["scopes_supported"]).to include("offline_access", "online_access")
      expect(body["capabilities"]).to include("permission-offline", "permission-online")
    end
  end
end
