require "rails_helper"

RSpec.describe "OAuth token endpoint (POST /oauth/token)", type: :request do
  let!(:registration) { OauthClient.register(name: "test-client", scopes: "system/*.read system/Patient.write") }
  let(:client) { registration.first }
  let(:secret) { registration.last }

  it "issues a token via client_secret_post with the client's full scopes" do
    post "/oauth/token", params: { grant_type: "client_credentials", client_id: client.id, client_secret: secret }

    expect(response).to have_http_status(:ok)
    expect(response.headers["Cache-Control"]).to include("no-store")
    body = JSON.parse(response.body)
    expect(body["token_type"]).to eq("bearer")
    expect(body["expires_in"]).to eq(3600)
    expect(body["scope"]).to eq("system/*.read system/Patient.write")
    expect(AccessToken.authenticate(body["access_token"])).to be_present
  end

  it "issues a token via HTTP Basic client authentication" do
    credentials = Base64.strict_encode64("#{client.id}:#{secret}")

    post "/oauth/token", params: { grant_type: "client_credentials" },
                         headers: { "Authorization" => "Basic #{credentials}" }

    expect(response).to have_http_status(:ok)
  end

  it "narrows to the requested scope subset" do
    post "/oauth/token", params: { grant_type: "client_credentials", client_id: client.id,
                                   client_secret: secret, scope: "system/*.read" }

    expect(JSON.parse(response.body)["scope"]).to eq("system/*.read")
  end

  it "rejects a scope outside the registration with invalid_scope" do
    post "/oauth/token", params: { grant_type: "client_credentials", client_id: client.id,
                                   client_secret: secret, scope: "system/*.*" }

    expect(response).to have_http_status(:bad_request)
    expect(JSON.parse(response.body)["error"]).to eq("invalid_scope")
  end

  it "rejects bad credentials with 401 invalid_client" do
    post "/oauth/token", params: { grant_type: "client_credentials", client_id: client.id, client_secret: "wrong" }

    expect(response).to have_http_status(:unauthorized)
    expect(JSON.parse(response.body)["error"]).to eq("invalid_client")
  end

  it "rejects other grant types with unsupported_grant_type" do
    post "/oauth/token", params: { grant_type: "authorization_code", client_id: client.id, client_secret: secret }

    expect(response).to have_http_status(:bad_request)
    expect(JSON.parse(response.body)["error"]).to eq("unsupported_grant_type")
  end

  describe "private_key_jwt (JWT client assertion)" do
    def b64url(data)
      Base64.urlsafe_encode64(data, padding: false)
    end

    def signed_assertion(key, client_id)
      header = { "alg" => "RS384", "typ" => "JWT", "kid" => "key-1" }
      claims = {
        "iss" => client_id, "sub" => client_id,
        "aud" => "http://www.example.com/oauth/token",
        "exp" => 4.minutes.from_now.to_i, "jti" => SecureRandom.uuid
      }
      input = "#{b64url(header.to_json)}.#{b64url(claims.to_json)}"
      "#{input}.#{b64url(key.sign(OpenSSL::Digest::SHA384.new, input))}"
    end

    let(:private_key) { OpenSSL::PKey::RSA.new(2048) }
    let(:jwks) do
      { "keys" => [{ "kty" => "RSA", "kid" => "key-1", "alg" => "RS384",
                     "n" => b64url(private_key.n.to_s(2)), "e" => b64url(private_key.e.to_s(2)) }] }
    end
    let(:jwt_client) { OauthClient.register(name: "jwt-client", scopes: "system/*.read", jwks: jwks).first }

    it "issues a token for a valid assertion" do
      post "/oauth/token", params: {
        grant_type: "client_credentials",
        client_assertion_type: Fhir::ClientAssertion::JWT_BEARER_TYPE,
        client_assertion: signed_assertion(private_key, jwt_client.id)
      }

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["scope"]).to eq("system/*.read")
      expect(AccessToken.authenticate(body["access_token"]).oauth_client_id).to eq(jwt_client.id)
    end

    it "rejects an invalid assertion with invalid_client and a reason" do
      post "/oauth/token", params: {
        grant_type: "client_credentials",
        client_assertion_type: Fhir::ClientAssertion::JWT_BEARER_TYPE,
        client_assertion: signed_assertion(OpenSSL::PKey::RSA.new(2048), jwt_client.id)
      }

      expect(response).to have_http_status(:unauthorized)
      body = JSON.parse(response.body)
      expect(body["error"]).to eq("invalid_client")
      expect(body["error_description"]).to include("Signature verification failed")
    end

    it "does not allow a JWKS client to authenticate with a secret" do
      post "/oauth/token", params: { grant_type: "client_credentials", client_id: jwt_client.id, client_secret: "anything" }

      expect(response).to have_http_status(:unauthorized)
    end

    it "advertises private_key_jwt in the SMART configuration" do
      get "/.well-known/smart-configuration"

      body = JSON.parse(response.body)
      expect(body["token_endpoint_auth_methods_supported"]).to include("private_key_jwt")
      expect(body["token_endpoint_auth_signing_alg_values_supported"]).to eq(%w[RS384 ES384])
      expect(body["capabilities"]).to include("client-confidential-asymmetric")
    end
  end
end
