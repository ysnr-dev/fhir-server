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
end
