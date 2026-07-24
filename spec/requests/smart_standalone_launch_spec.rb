require "rails_helper"

# The interactive standalone launch end to end: authorize -> login -> consent
# -> code -> token -> compartment-restricted API access.
RSpec.describe "SMART standalone launch", type: :request do
  around { |example| with_fhir_auth { example.run } }

  let(:system_token) { issue_access_token(scopes: "system/*.*") }
  let(:redirect_uri) { "https://app.example/cb" }
  let(:verifier) { "a" * 64 }
  let(:challenge) { Base64.urlsafe_encode64(OpenSSL::Digest::SHA256.digest(verifier), padding: false) }
  let(:password) { "correct-horse-battery" }

  let!(:patient_id) do
    post "/Patient", params: valid_patient_payload.to_json,
                     headers: bearer_header(system_token).merge("CONTENT_TYPE" => "application/json")
    JSON.parse(response.body)["id"]
  end
  let!(:user) { register_user(patient_id: patient_id, email: "p@example.com", password: password) }

  let(:client) do
    OauthClient.register(
      name: "My Health App", scopes: "patient/*.read",
      redirect_uris: redirect_uri, client_type: "public"
    ).first
  end

  def authorize_params(**overrides)
    {
      response_type: "code", client_id: client.id, redirect_uri: redirect_uri,
      scope: "patient/*.read", state: "xyz-state",
      code_challenge: challenge, code_challenge_method: "S256"
    }.merge(overrides)
  end

  def redirect_query
    Rack::Utils.parse_query(URI.parse(response.headers["Location"]).query)
  end

  # Drives the browser half of the flow and returns the issued code.
  def obtain_code(**overrides)
    post "/oauth/login", params: authorize_params(**overrides).merge(email: user.email, password: password)
    expect(response).to have_http_status(:ok)

    post "/oauth/consent", params: authorize_params(**overrides).merge(decision: "approve")
    expect(response).to have_http_status(:found)
    redirect_query["code"]
  end

  describe "GET /oauth/authorize" do
    it "renders the login form" do
      get "/oauth/authorize", params: authorize_params

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("My Health App")
    end

    # Stage 1 failures have no verified redirect_uri to send errors to, so they
    # must render rather than redirect -- otherwise this is an open redirector.
    it "renders a 400 for an unknown client_id instead of redirecting" do
      get "/oauth/authorize", params: authorize_params(client_id: "no-such-client")

      expect(response).to have_http_status(:bad_request)
      expect(response.headers["Location"]).to be_nil
    end

    it "renders a 400 for an unregistered redirect_uri instead of redirecting" do
      get "/oauth/authorize", params: authorize_params(redirect_uri: "https://evil.example/steal")

      expect(response).to have_http_status(:bad_request)
      expect(response.headers["Location"]).to be_nil
    end

    it "rejects a backend client that has no redirect_uri at all" do
      backend, = OauthClient.register(name: "backend", scopes: "system/*.read")

      get "/oauth/authorize", params: authorize_params(client_id: backend.id)

      expect(response).to have_http_status(:bad_request)
    end

    # Stage 2: the redirect_uri is verified by now, so errors go back to the app.
    it "redirects with an error when PKCE is missing" do
      get "/oauth/authorize", params: authorize_params.except(:code_challenge)

      expect(response).to redirect_to(/\Ahttps:\/\/app\.example\/cb\?/)
      expect(redirect_query).to include("error" => "invalid_request", "state" => "xyz-state")
    end

    it "redirects with an error for a non-S256 challenge method" do
      get "/oauth/authorize", params: authorize_params(code_challenge_method: "plain")

      expect(redirect_query["error"]).to eq("invalid_request")
    end

    it "redirects with an error for a non-code response_type" do
      get "/oauth/authorize", params: authorize_params(response_type: "token")

      expect(redirect_query["error"]).to eq("unsupported_response_type")
    end

    it "redirects with an error for a system scope" do
      get "/oauth/authorize", params: authorize_params(scope: "system/*.read")

      expect(redirect_query["error"]).to eq("invalid_scope")
    end

    it "redirects with an error when the scope exceeds the registration" do
      narrow = OauthClient.register(
        name: "narrow", scopes: "patient/Observation.read",
        redirect_uris: redirect_uri, client_type: "public"
      ).first

      get "/oauth/authorize", params: authorize_params(client_id: narrow.id, scope: "patient/*.read")

      expect(redirect_query["error"]).to eq("invalid_scope")
    end
  end

  describe "POST /oauth/login" do
    it "re-renders with a generic error on a bad password" do
      post "/oauth/login", params: authorize_params.merge(email: user.email, password: "wrong")

      expect(response).to have_http_status(:unauthorized)
      expect(response.body).to include("メールアドレスまたはパスワードが正しくありません")
    end

    it "records the failure for the brute-force ban" do
      expect(Fhir::AuthThrottle).to receive(:register_failure!)

      post "/oauth/login", params: authorize_params.merge(email: user.email, password: "wrong")
    end

    it "shows the consent screen on success" do
      post "/oauth/login", params: authorize_params.merge(email: user.email, password: password)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("アクセスの許可")
    end
  end

  describe "POST /oauth/consent" do
    it "issues a code carrying the patient context and echoes the state" do
      code = obtain_code

      expect(code).to be_present
      expect(redirect_query["state"]).to eq("xyz-state")
      expect(AuthorizationCode.last.patient_id).to eq(patient_id)
    end

    it "redirects with access_denied when the user declines" do
      post "/oauth/login", params: authorize_params.merge(email: user.email, password: password)
      post "/oauth/consent", params: authorize_params.merge(decision: "deny")

      expect(redirect_query["error"]).to eq("access_denied")
      expect(redirect_query["code"]).to be_nil
    end

    it "refuses to issue a code without a session" do
      post "/oauth/consent", params: authorize_params.merge(decision: "approve")

      expect(response).to have_http_status(:unauthorized)
      expect(AuthorizationCode.count).to eq(0)
    end
  end

  describe "POST /oauth/token (authorization_code)" do
    def exchange(**overrides)
      post "/oauth/token", params: {
        grant_type: "authorization_code", code: obtain_code, redirect_uri: redirect_uri,
        client_id: client.id, code_verifier: verifier
      }.merge(overrides)
    end

    it "returns a token with the patient launch context" do
      exchange

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["token_type"]).to eq("bearer")
      expect(body["scope"]).to eq("patient/*.read")
      expect(body["patient"]).to eq(patient_id)
    end

    it "rejects a wrong code_verifier" do
      exchange(code_verifier: "b" * 64)

      expect(response).to have_http_status(:bad_request)
      expect(JSON.parse(response.body)["error"]).to eq("invalid_grant")
    end

    it "rejects a missing code_verifier" do
      exchange(code_verifier: nil)

      expect(JSON.parse(response.body)["error"]).to eq("invalid_grant")
    end

    it "rejects a mismatched redirect_uri" do
      exchange(redirect_uri: "https://app.example/other")

      expect(JSON.parse(response.body)["error"]).to eq("invalid_grant")
    end

    it "rejects an unknown code" do
      post "/oauth/token", params: {
        grant_type: "authorization_code", code: "nope", redirect_uri: redirect_uri,
        client_id: client.id, code_verifier: verifier
      }

      expect(JSON.parse(response.body)["error"]).to eq("invalid_grant")
    end

    it "rejects an expired code" do
      code = obtain_code
      AuthorizationCode.update_all(expires_at: 1.minute.ago)

      post "/oauth/token", params: {
        grant_type: "authorization_code", code: code, redirect_uri: redirect_uri,
        client_id: client.id, code_verifier: verifier
      }

      expect(JSON.parse(response.body)["error"]).to eq("invalid_grant")
    end

    it "rejects a public client presenting someone else's client_id" do
      other, = OauthClient.register(name: "other", scopes: "patient/*.read",
                                    redirect_uris: redirect_uri, client_type: "public")

      exchange(client_id: other.id)

      expect(response).to have_http_status(:unauthorized)
      expect(JSON.parse(response.body)["error"]).to eq("invalid_client")
    end

    # A replayed code means it leaked, so the tokens it already produced are in
    # the attacker's hands too.
    it "revokes the tokens a replayed code produced" do
      code = obtain_code
      params = { grant_type: "authorization_code", code: code, redirect_uri: redirect_uri,
                 client_id: client.id, code_verifier: verifier }

      post "/oauth/token", params: params
      token = JSON.parse(response.body)["access_token"]

      post "/oauth/token", params: params
      expect(JSON.parse(response.body)["error"]).to eq("invalid_grant")

      get "/Patient/#{patient_id}", headers: bearer_header(token)
      expect(response).to have_http_status(:unauthorized)
    end

    it "authenticates a confidential client with its secret" do
      confidential, secret = OauthClient.register(
        name: "server-side app", scopes: "patient/*.read",
        redirect_uris: redirect_uri, client_type: "confidential"
      )
      post "/oauth/login", params: authorize_params(client_id: confidential.id)
                             .merge(email: user.email, password: password)
      post "/oauth/consent", params: authorize_params(client_id: confidential.id).merge(decision: "approve")
      code = redirect_query["code"]

      post "/oauth/token", params: {
        grant_type: "authorization_code", code: code, redirect_uri: redirect_uri,
        client_id: confidential.id, client_secret: secret, code_verifier: verifier
      }

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["patient"]).to eq(patient_id)
    end
  end

  it "completes the whole flow and confines API access to the launch patient" do
    other_patient = begin
      post "/Patient", params: valid_patient_payload.to_json,
                       headers: bearer_header(system_token).merge("CONTENT_TYPE" => "application/json")
      JSON.parse(response.body)["id"]
    end

    post "/oauth/token", params: {
      grant_type: "authorization_code", code: obtain_code, redirect_uri: redirect_uri,
      client_id: client.id, code_verifier: verifier
    }
    token = JSON.parse(response.body)["access_token"]

    get "/Patient/#{patient_id}", headers: bearer_header(token)
    expect(response).to have_http_status(:ok)

    get "/Patient/#{other_patient}", headers: bearer_header(token)
    expect(response).to have_http_status(:not_found)
  end

  describe "discovery" do
    it "advertises the authorization endpoint and PKCE" do
      get "/.well-known/smart-configuration"

      body = JSON.parse(response.body)
      expect(body["authorization_endpoint"]).to end_with("/oauth/authorize")
      expect(body["grant_types_supported"]).to include("authorization_code")
      expect(body["code_challenge_methods_supported"]).to eq(["S256"])
      expect(body["capabilities"]).to include("launch-standalone", "context-standalone-patient")
    end

    it "advertises both v1 and v2 permission support" do
      get "/.well-known/smart-configuration"

      body = JSON.parse(response.body)
      expect(body["capabilities"]).to include("permission-v1", "permission-v2")
      expect(body["scopes_supported"]).to include("system/*.cruds", "patient/*.rs")
    end

    it "advertises the authorize URI in the CapabilityStatement" do
      get "/metadata"

      uris = JSON.parse(response.body)["rest"].first["security"]["extension"].first["extension"]
      expect(uris.find { |uri| uri["url"] == "authorize" }["valueUri"]).to end_with("/oauth/authorize")
    end
  end
end
