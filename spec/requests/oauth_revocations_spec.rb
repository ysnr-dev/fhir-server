require "rails_helper"

RSpec.describe "OAuth token revocation (POST /oauth/revoke)", type: :request do
  let!(:registration) { OauthClient.register(name: "revoke-client", scopes: "system/*.read") }
  let(:client) { registration.first }
  let(:secret) { registration.last }

  def issue_token_for(target_client)
    _record, raw = AccessToken.issue(target_client, scopes: ["system/*.read"])
    raw
  end

  it "revokes the client's own token via client_secret_post" do
    raw = issue_token_for(client)

    post "/oauth/revoke", params: { client_id: client.id, client_secret: secret, token: raw }

    expect(response).to have_http_status(:ok)
    expect(response.body).to be_empty
    expect(response.headers["Cache-Control"]).to include("no-store")
    expect(AccessToken.authenticate(raw)).to be_revoked
  end

  it "revokes via HTTP Basic client authentication" do
    raw = issue_token_for(client)
    credentials = Base64.strict_encode64("#{client.id}:#{secret}")

    post "/oauth/revoke", params: { token: raw }, headers: { "Authorization" => "Basic #{credentials}" }

    expect(response).to have_http_status(:ok)
    expect(AccessToken.authenticate(raw)).to be_revoked
  end

  it "returns 200 for an unknown token without revealing anything" do
    post "/oauth/revoke", params: { client_id: client.id, client_secret: secret, token: "no-such-token" }

    expect(response).to have_http_status(:ok)
    expect(response.body).to be_empty
  end

  it "returns 200 but does not revoke another client's token" do
    other_client, = OauthClient.register(name: "other-client", scopes: "system/*.read")
    raw = issue_token_for(other_client)

    post "/oauth/revoke", params: { client_id: client.id, client_secret: secret, token: raw }

    expect(response).to have_http_status(:ok)
    expect(AccessToken.authenticate(raw)).not_to be_revoked
  end

  it "rejects bad client credentials with 401 invalid_client" do
    post "/oauth/revoke", params: { client_id: client.id, client_secret: "wrong", token: "x" }

    expect(response).to have_http_status(:unauthorized)
    expect(JSON.parse(response.body)["error"]).to eq("invalid_client")
  end

  it "rejects a revoked token on FHIR endpoints with 401" do
    with_fhir_auth do
      raw = issue_token_for(client)

      get "/Patient", headers: bearer_header(raw)
      expect(response).to have_http_status(:ok)

      post "/oauth/revoke", params: { client_id: client.id, client_secret: secret, token: raw }
      expect(response).to have_http_status(:ok)

      get "/Patient", headers: bearer_header(raw)
      expect(response).to have_http_status(:unauthorized)
      expect(JSON.parse(response.body)["issue"].first["diagnostics"]).to include("revoked")
    end
  end

  describe "private_key_jwt client authentication" do
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
    let(:jwt_client) { OauthClient.register(name: "jwt-revoke-client", scopes: "system/*.read", jwks: jwks).first }

    it "revokes with a valid assertion" do
      raw = issue_token_for(jwt_client)

      post "/oauth/revoke", params: {
        client_assertion_type: Fhir::ClientAssertion::JWT_BEARER_TYPE,
        client_assertion: signed_assertion(private_key, jwt_client.id),
        token: raw
      }

      expect(response).to have_http_status(:ok)
      expect(AccessToken.authenticate(raw)).to be_revoked
    end
  end

  it "advertises the revocation endpoint in the SMART configuration" do
    get "/.well-known/smart-configuration"

    expect(JSON.parse(response.body)["revocation_endpoint"]).to eq("http://www.example.com/oauth/revoke")
  end
end
