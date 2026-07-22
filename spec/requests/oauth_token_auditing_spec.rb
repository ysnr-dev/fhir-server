require "rails_helper"

RSpec.describe "OAuth endpoint auditing", type: :request do
  let!(:registration) { OauthClient.register(name: "audited-client", scopes: "system/*.read") }
  let(:client) { registration.first }
  let(:secret) { registration.last }

  it "records an AuditEvent attributed to the client for a successful token issue" do
    expect {
      post "/oauth/token", params: { grant_type: "client_credentials", client_id: client.id, client_secret: secret }
    }.to change(AuditEvent, :count).by(1)

    event = AuditEvent.order(:occurred_at).last
    expect(event.client_id).to eq(client.id)
    expect(event.client_name).to eq("audited-client")
    expect(event.interaction).to eq("operation")
    expect(event.request_path).to eq("/oauth/token")
    expect(event.response_status).to eq(200)
  end

  it "records a client-less AuditEvent for a failed client authentication" do
    expect {
      post "/oauth/token", params: { grant_type: "client_credentials", client_id: client.id, client_secret: "wrong" }
    }.to change(AuditEvent, :count).by(1)

    event = AuditEvent.order(:occurred_at).last
    expect(event.client_id).to be_nil
    expect(event.response_status).to eq(401)
  end

  it "records an AuditEvent for a revocation request" do
    _record, raw = AccessToken.issue(client, scopes: ["system/*.read"])

    expect {
      post "/oauth/revoke", params: { client_id: client.id, client_secret: secret, token: raw }
    }.to change(AuditEvent, :count).by(1)

    event = AuditEvent.order(:occurred_at).last
    expect(event.client_id).to eq(client.id)
    expect(event.request_path).to eq("/oauth/revoke")
    expect(event.response_status).to eq(200)
  end

  it "does not audit /metadata or the SMART discovery document" do
    expect {
      get "/metadata"
      get "/.well-known/smart-configuration"
    }.not_to change(AuditEvent, :count)
  end
end
