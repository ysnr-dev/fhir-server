require "rails_helper"

# The OpenID Connect identity layer of the standalone launch: openid / fhirUser
# consented at authorization -> id_token returned at the code exchange ->
# verifiable against /.well-known/jwks.json.
RSpec.describe "OAuth OpenID Connect identity", type: :request do
  around { |example| with_fhir_auth { example.run } }

  let(:system_token) { issue_access_token(scopes: "system/*.*") }
  let(:redirect_uri) { "https://app.example/cb" }
  let(:verifier) { "a" * 64 }
  let(:challenge) { Base64.urlsafe_encode64(OpenSSL::Digest::SHA256.digest(verifier), padding: false) }
  let(:password) { "correct-horse-battery" }
  let(:scope) { "patient/*.read openid fhirUser" }

  let!(:patient_id) do
    post "/Patient", params: valid_patient_payload.to_json,
                     headers: bearer_header(system_token).merge("CONTENT_TYPE" => "application/json")
    JSON.parse(response.body)["id"]
  end
  let!(:user) { register_user(patient_id: patient_id, email: "p@example.com", password: password) }

  let(:client) do
    OauthClient.register(
      name: "My Health App", scopes: "patient/*.read openid fhirUser profile offline_access",
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

  def obtain_tokens(**overrides)
    post "/oauth/login", params: authorize_params(**overrides).merge(email: user.email, password: password)
    expect(response).to have_http_status(:ok)
    post "/oauth/consent", params: authorize_params(**overrides).merge(decision: "approve")
    expect(response).to have_http_status(:found)
    code = Rack::Utils.parse_query(URI.parse(response.headers["Location"]).query)["code"]

    post "/oauth/token", params: {
      grant_type: "authorization_code", code: code, redirect_uri: redirect_uri,
      client_id: client.id, code_verifier: verifier
    }
    expect(response).to have_http_status(:ok)
    JSON.parse(response.body)
  end

  describe "id_token at the code exchange" do
    it "returns a verifiable id_token identifying the launch user" do
      body = obtain_tokens

      expect(body["id_token"]).to be_present
      header, claims = decode_jwt(body["id_token"])

      # Verifies against the key the server publishes.
      jwks = JSON.parse(get_jwks)
      expect(header["kid"]).to eq(jwks["keys"].first["kid"])
      expect(jwt_signature_valid?(body["id_token"], jwks["keys"].first)).to be(true)

      expect(claims["iss"]).to eq("http://www.example.com")
      expect(claims["aud"]).to eq(client.id)
      expect(claims["sub"]).to eq(user.id.to_s)
      expect(claims["fhirUser"]).to eq("http://www.example.com/Patient/#{patient_id}")
    end

    it "binds the nonce from the authorization request" do
      body = obtain_tokens(nonce: "n-abc-123")

      _header, claims = decode_jwt(body["id_token"])
      expect(claims["nonce"]).to eq("n-abc-123")
    end

    it "omits fhirUser when only openid was consented" do
      body = obtain_tokens(scope: "patient/*.read openid")

      _header, claims = decode_jwt(body["id_token"])
      expect(claims).not_to have_key("fhirUser")
    end

    it "returns no id_token when openid was not requested" do
      body = obtain_tokens(scope: "patient/*.read")

      expect(body).not_to have_key("id_token")
    end

    it "does not issue an id_token on refresh" do
      body = obtain_tokens(scope: "patient/*.read openid offline_access")
      expect(body["id_token"]).to be_present

      post "/oauth/token", params: {
        grant_type: "refresh_token", refresh_token: body["refresh_token"], client_id: client.id
      }
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).not_to have_key("id_token")
    end
  end

  describe "GET /.well-known/jwks.json" do
    it "publishes the public signing key" do
      jwks = JSON.parse(get_jwks)

      key = jwks["keys"].first
      expect(key).to include("kty" => "RSA", "use" => "sig", "alg" => "RS384")
      expect(key).to have_key("kid")
      expect(key).not_to have_key("d")
      expect(response.headers["Cache-Control"]).to include("max-age")
    end
  end

  describe "discovery" do
    it "advertises the OpenID Connect identity layer" do
      get "/.well-known/smart-configuration"
      body = JSON.parse(response.body)

      expect(body["issuer"]).to eq("http://www.example.com")
      expect(body["jwks_uri"]).to end_with("/.well-known/jwks.json")
      expect(body["id_token_signing_alg_values_supported"]).to eq(["RS384"])
      expect(body["scopes_supported"]).to include("openid", "fhirUser", "profile")
      expect(body["capabilities"]).to include("sso-openid-connect")
    end
  end

  # jwks endpoint is public; fetch it without disturbing the auth-enabled block.
  def get_jwks
    get "/.well-known/jwks.json"
    expect(response).to have_http_status(:ok)
    response.body
  end
end
