require "rails_helper"

# The EHR launch end to end: the EHR mints a launch context through the admin
# API -> the app hits /oauth/authorize with launch + aud and is redirected
# straight back with a code (no login, no consent, no session) -> token exchange
# carries the practitioner/patient/encounter context -> user/ tokens reach every
# patient while patient/ tokens stay in their compartment.
RSpec.describe "SMART EHR launch", type: :request do
  around { |example| with_fhir_auth { example.run } }

  let(:admin_token) { "a" * 64 }
  around do |example|
    previous = ENV["FHIR_ADMIN_TOKEN"]
    ENV["FHIR_ADMIN_TOKEN"] = admin_token
    example.run
  ensure
    ENV["FHIR_ADMIN_TOKEN"] = previous
  end

  let(:system_token) { issue_access_token(scopes: "system/*.*") }
  let(:redirect_uri) { "https://app.example/cb" }
  let(:verifier) { "a" * 64 }
  let(:challenge) { Base64.urlsafe_encode64(OpenSSL::Digest::SHA256.digest(verifier), padding: false) }
  # Request specs run against www.example.com; aud must name exactly this server.
  let(:issuer) { "http://www.example.com" }

  def create_resource(type, payload)
    post "/#{type}", params: payload.to_json,
                     headers: bearer_header(system_token).merge("CONTENT_TYPE" => "application/json")
    expect(response).to have_http_status(:created)
    JSON.parse(response.body)["id"]
  end

  let!(:patient_id) { create_resource("Patient", valid_patient_payload) }
  let!(:other_patient_id) { create_resource("Patient", valid_patient_payload) }
  let!(:practitioner_id) { create_resource("Practitioner", valid_practitioner_payload) }
  let!(:encounter_id) do
    create_resource("Encounter", valid_encounter_payload("subject" => { "reference" => "Patient/#{patient_id}" }))
  end

  let(:scopes) { "user/*.read launch launch/patient launch/encounter openid fhirUser online_access" }
  let(:client) do
    OauthClient.register(name: "Karte App", scopes: scopes, redirect_uris: redirect_uri, client_type: "public").first
  end

  def mint_launch(**overrides)
    body = { client_id: client.id, patient_id: patient_id, encounter_id: encounter_id,
             practitioner_id: practitioner_id, issued_by: "fhir-client" }.merge(overrides)
    post "/admin/launch_contexts", params: body.to_json,
                                   headers: { "X-FHIR-Admin-Token" => admin_token, "CONTENT_TYPE" => "application/json" }
    expect(response).to have_http_status(:created)
    JSON.parse(response.body)["launch"]
  end

  def authorize_params(**overrides)
    {
      response_type: "code", client_id: client.id, redirect_uri: redirect_uri,
      scope: "user/*.read launch openid fhirUser", state: "xyz-state", aud: issuer,
      code_challenge: challenge, code_challenge_method: "S256", launch: mint_launch
    }.merge(overrides)
  end

  def redirect_query
    Rack::Utils.parse_query(URI.parse(response.headers["Location"]).query)
  end

  def exchange(code)
    post "/oauth/token", params: { grant_type: "authorization_code", code: code, redirect_uri: redirect_uri,
                                   client_id: client.id, code_verifier: verifier }
    JSON.parse(response.body)
  end

  def decode_jwt_payload(jwt)
    payload = jwt.split(".")[1]
    JSON.parse(Base64.urlsafe_decode64(payload + "=" * (-payload.length % 4)))
  end

  describe "GET /oauth/authorize with launch" do
    it "redirects straight back with a code, rendering nothing and setting no session" do
      get "/oauth/authorize", params: authorize_params

      expect(response).to have_http_status(:found)
      expect(response.body).to be_blank
      expect(response.headers["Location"]).to start_with(redirect_uri)
      expect(redirect_query["code"]).to be_present
      expect(redirect_query["state"]).to eq("xyz-state")
      expect(response.headers["Set-Cookie"].to_s).not_to include("_session")
    end

    it "consumes the launch token so it cannot be replayed" do
      params = authorize_params
      get "/oauth/authorize", params: params
      expect(redirect_query["code"]).to be_present

      get "/oauth/authorize", params: params
      expect(redirect_query["error"]).to eq("invalid_request")
      expect(redirect_query["error_description"]).to include("launch token")
    end

    it "rejects an expired launch token" do
      params = authorize_params
      travel 6.minutes do
        get "/oauth/authorize", params: params
      end

      expect(redirect_query["error"]).to eq("invalid_request")
    end

    it "rejects a launch token minted for another client" do
      other, = OauthClient.register(name: "Other", scopes: scopes, redirect_uris: redirect_uri, client_type: "public")
      launch = mint_launch(client_id: other.id)

      get "/oauth/authorize", params: authorize_params(launch: launch)

      expect(redirect_query["error"]).to eq("invalid_request")
      expect(LaunchContext.last.used?).to be(false)
    end

    it "rejects a wrong aud without consuming the token" do
      get "/oauth/authorize", params: authorize_params(aud: "https://other-fhir.example")

      expect(redirect_query["error"]).to eq("invalid_request")
      expect(redirect_query["error_description"]).to include("aud")
      expect(LaunchContext.last.used?).to be(false)
    end

    it "accepts aud with a trailing slash" do
      get "/oauth/authorize", params: authorize_params(aud: "#{issuer}/")

      expect(redirect_query["code"]).to be_present
    end

    it "requires the launch scope" do
      get "/oauth/authorize", params: authorize_params(scope: "user/*.read openid")

      expect(redirect_query["error"]).to eq("invalid_scope")
      expect(redirect_query["error_description"]).to include("launch")
    end

    it "refuses offline_access" do
      client.update!(scopes: "#{scopes} offline_access")
      get "/oauth/authorize", params: authorize_params(scope: "user/*.read launch offline_access")

      expect(redirect_query["error"]).to eq("invalid_scope")
      expect(redirect_query["error_description"]).to include("offline_access")
    end

    it "still refuses scopes beyond the registration" do
      get "/oauth/authorize", params: authorize_params(scope: "user/*.write launch")

      expect(redirect_query["error"]).to eq("invalid_scope")
      expect(redirect_query["error_description"]).to include("registration")
    end

    it "is not accepted by the login and consent steps" do
      post "/oauth/login", params: authorize_params.merge(email: "x@example.com", password: "whatever")

      expect(response).to have_http_status(:found)
      expect(redirect_query["error"]).to eq("invalid_request")
    end

    it "keeps rendering the 400 page for an unknown client even with a launch token" do
      get "/oauth/authorize", params: authorize_params(client_id: "no-such-client", launch: "whatever")

      expect(response).to have_http_status(:bad_request)
      expect(response.headers["Location"]).to be_nil
    end
  end

  describe "standalone launch" do
    it "does not accept user/ or launch scopes without a launch token" do
      get "/oauth/authorize", params: authorize_params(launch: nil)

      expect(redirect_query["error"]).to eq("invalid_scope")
    end
  end

  describe "token exchange" do
    it "returns the launch context and identifies the practitioner" do
      get "/oauth/authorize", params: authorize_params(scope: "user/*.read launch launch/encounter openid fhirUser online_access")
      body = exchange(redirect_query["code"])

      expect(response).to have_http_status(:ok)
      expect(body["patient"]).to eq(patient_id)
      expect(body["encounter"]).to eq(encounter_id)
      expect(body["need_patient_banner"]).to be(false)
      expect(body["refresh_token"]).to be_present
      expect(body["scope"]).to include("user/*.read")

      claims = decode_jwt_payload(body["id_token"])
      expect(claims["sub"]).to eq("Practitioner/#{practitioner_id}")
      expect(claims["fhirUser"]).to eq("#{issuer}/Practitioner/#{practitioner_id}")
    end

    it "carries the practitioner and encounter through a refresh" do
      get "/oauth/authorize", params: authorize_params(scope: "user/*.read launch online_access")
      first = exchange(redirect_query["code"])

      post "/oauth/token", params: { grant_type: "refresh_token", refresh_token: first["refresh_token"], client_id: client.id }
      body = JSON.parse(response.body)

      expect(response).to have_http_status(:ok)
      expect(body["patient"]).to eq(patient_id)
      expect(body["encounter"]).to eq(encounter_id)
      refreshed = AccessToken.authenticate(body["access_token"])
      expect(refreshed.practitioner_id).to eq(practitioner_id)
      expect(refreshed.encounter_id).to eq(encounter_id)
    end

    it "reports need_patient_banner as the EHR said" do
      get "/oauth/authorize", params: authorize_params(launch: mint_launch(need_patient_banner: true))
      body = exchange(redirect_query["code"])

      expect(body["need_patient_banner"]).to be(true)
    end

    it "introspects the practitioner context" do
      get "/oauth/authorize", params: authorize_params
      body = exchange(redirect_query["code"])
      confidential, secret = OauthClient.register(name: "rs", scopes: "system/*.read")

      post "/oauth/introspect", params: { token: body["access_token"], client_id: confidential.id, client_secret: secret }
      claims = JSON.parse(response.body)

      expect(claims["active"]).to be(true)
      expect(claims["sub"]).to eq("Practitioner/#{practitioner_id}")
      expect(claims["fhirUser"]).to eq("#{issuer}/Practitioner/#{practitioner_id}")
      expect(claims["patient"]).to eq(patient_id)
      expect(claims["encounter"]).to eq(encounter_id)
    end
  end

  describe "access with a user/ token" do
    def user_token(scope = "user/*.read launch")
      get "/oauth/authorize", params: authorize_params(scope: scope)
      exchange(redirect_query["code"])["access_token"]
    end

    it "reads any patient, not just the launch patient" do
      token = user_token

      get "/Patient/#{other_patient_id}", headers: bearer_header(token)
      expect(response).to have_http_status(:ok)

      get "/Patient", headers: bearer_header(token)
      ids = JSON.parse(response.body)["entry"].map { |e| e["resource"]["id"] }
      expect(ids).to include(patient_id, other_patient_id)
    end

    it "is still refused the system-only interactions" do
      token = user_token

      get "/AuditEvent", headers: bearer_header(token)
      expect(response).to have_http_status(:forbidden)

      get "/_history", headers: bearer_header(token)
      expect(response).to have_http_status(:forbidden)
    end

    it "writes when the registration allows it, and names user/ in the 403 otherwise" do
      token = user_token
      post "/Patient", params: valid_patient_payload.to_json,
                       headers: bearer_header(token).merge("CONTENT_TYPE" => "application/json")
      expect(response).to have_http_status(:forbidden)
      expect(JSON.parse(response.body)["issue"].first["diagnostics"]).to include("user/Patient.write")

      client.update!(scopes: "#{scopes} user/Patient.cud")
      writer = user_token("user/*.read user/Patient.cud launch")
      post "/Patient", params: valid_patient_payload.to_json,
                       headers: bearer_header(writer).merge("CONTENT_TYPE" => "application/json")
      expect(response).to have_http_status(:created)
    end

    it "attributes audited requests to the app and the practitioner" do
      token = user_token
      get "/Patient/#{patient_id}", headers: bearer_header(token)

      event = AuditEvent.order(:occurred_at).last
      expect(event.client_id).to eq(client.id)
      expect(event.agent_who_reference).to eq("Practitioner/#{practitioner_id}")
      expect(event.to_fhir.dig("agent", 0, "who", "reference")).to eq("Practitioner/#{practitioner_id}")
    end
  end

  describe "access with a patient/ token from an EHR launch" do
    let(:scopes) { "patient/*.read launch" }

    it "stays confined to the launch patient" do
      get "/oauth/authorize", params: authorize_params(scope: "patient/*.read launch")
      token = exchange(redirect_query["code"])["access_token"]

      get "/Patient/#{patient_id}", headers: bearer_header(token)
      expect(response).to have_http_status(:ok)

      get "/Patient/#{other_patient_id}", headers: bearer_header(token)
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "client_credentials" do
    it "is refused to launch clients" do
      confidential, secret = OauthClient.register(name: "srv", scopes: scopes, redirect_uris: redirect_uri)

      post "/oauth/token", params: { grant_type: "client_credentials", client_id: confidential.id, client_secret: secret }

      expect(response).to have_http_status(:bad_request)
      expect(JSON.parse(response.body)["error"]).to eq("unauthorized_client")
    end
  end

  describe "discovery" do
    it "advertises the EHR launch" do
      get "/.well-known/smart-configuration"
      body = JSON.parse(response.body)

      expect(body["capabilities"]).to include("launch-ehr", "context-ehr-patient", "context-ehr-encounter",
                                              "permission-user", "context-banner")
      expect(body["scopes_supported"]).to include("launch", "launch/patient", "user/*.read", "user/*.cud")
    end
  end
end
