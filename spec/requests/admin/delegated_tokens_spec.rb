require "rails_helper"

# CDS Hooks の fhirAuthorization 用の委任トークン。
RSpec.describe "Admin delegated tokens (/admin/delegated_tokens)", type: :request do
  let(:admin_token) { "a" * 64 }

  around do |example|
    previous = ENV["FHIR_ADMIN_TOKEN"]
    ENV["FHIR_ADMIN_TOKEN"] = admin_token
    example.run
  ensure
    ENV["FHIR_ADMIN_TOKEN"] = previous
  end

  def json_headers
    { "X-FHIR-Admin-Token" => admin_token, "CONTENT_TYPE" => "application/json" }
  end

  def create_resource(type, payload)
    post "/#{type}", params: payload.to_json, headers: { "CONTENT_TYPE" => "application/json" }
    JSON.parse(response.body)["id"]
  end

  let!(:patient_id) { create_resource("Patient", valid_patient_payload) }
  let!(:other_patient_id) { create_resource("Patient", valid_patient_payload) }
  let!(:practitioner_id) { create_resource("Practitioner", valid_practitioner_payload) }
  let(:client) { OauthClient.register(name: "CDS 薬剤安全", scopes: "user/*.cruds user/Observation.read").first }

  def issue(**overrides)
    body = { client_id: client.id, practitioner_id: practitioner_id, patient_id: patient_id }.merge(overrides)
    post "/admin/delegated_tokens", params: body.to_json, headers: json_headers
    JSON.parse(response.body)
  end

  it "registers a CDS service as a delegated client" do
    expect(client.delegated_client?).to be(true)
    expect(client.launch_client?).to be(false)
    expect(client.delegated_scopes).to eq(%w[user/*.read user/Observation.read])
  end

  it "refuses context scopes on a delegated client" do
    expect { OauthClient.register(name: "x", scopes: "user/*.read openid") }
      .to raise_error(ActiveRecord::RecordInvalid, /context scopes/)
  end

  it "issues a 5-minute read-only token in the fhirAuthorization shape" do
    body = issue

    expect(response).to have_http_status(:created)
    expect(body).to include("token_type" => "Bearer", "expires_in" => 300, "subject" => client.id,
                            "patient" => patient_id, "scope" => "user/*.read user/Observation.read")
    token = AccessToken.authenticate(body["access_token"])
    expect(token.practitioner_id).to eq(practitioner_id)
    expect(token.expires_at).to be_within(5.seconds).of(5.minutes.from_now)
  end

  it "lets the service read any patient but not write or reach system-only endpoints" do
    raw = issue["access_token"]

    with_fhir_auth do
      get "/Patient/#{other_patient_id}", headers: bearer_header(raw)
      expect(response).to have_http_status(:ok)

      post "/Patient", params: valid_patient_payload.to_json,
                       headers: bearer_header(raw).merge("CONTENT_TYPE" => "application/json")
      expect(response).to have_http_status(:forbidden)

      get "/AuditEvent", headers: bearer_header(raw)
      expect(response).to have_http_status(:forbidden)
    end
  end

  it "attributes the service's reads to the practitioner" do
    raw = issue["access_token"]

    with_fhir_auth { get "/Patient/#{patient_id}", headers: bearer_header(raw) }

    event = AuditEvent.where(request_path: "/Patient/#{patient_id}").order(:occurred_at).last
    expect(event.client_id).to eq(client.id)
    expect(event.agent_who_reference).to eq("Practitioner/#{practitioner_id}")
  end

  it "works without a patient" do
    body = issue(patient_id: nil)

    expect(response).to have_http_status(:created)
    expect(body).not_to have_key("patient")
  end

  it "refuses clients that are not delegated, and unknown people" do
    backend, = OauthClient.register(name: "backend", scopes: "system/*.read")
    launch, = OauthClient.register(name: "launch", scopes: "user/*.read launch", redirect_uris: "https://app.example/cb")

    issue(client_id: backend.id)
    expect(response).to have_http_status(:unprocessable_content)
    issue(client_id: launch.id)
    expect(response).to have_http_status(:unprocessable_content)

    issue(practitioner_id: "nope")
    expect(JSON.parse(response.body)["errors"]).to include("practitioner_id does not exist")
    issue(patient_id: "nope")
    expect(JSON.parse(response.body)["errors"]).to include("patient_id does not exist")
  end

  it "returns 400, 404 and 401 like the other admin APIs" do
    issue(practitioner_id: nil)
    expect(response).to have_http_status(:bad_request)

    issue(client_id: SecureRandom.uuid)
    expect(response).to have_http_status(:not_found)

    post "/admin/delegated_tokens", params: {}.to_json, headers: { "CONTENT_TYPE" => "application/json" }
    expect(response).to have_http_status(:unauthorized)
  end

  it "keeps delegated clients away from the token endpoint" do
    confidential, secret = OauthClient.register(name: "cds", scopes: "user/*.read")

    post "/oauth/token", params: { grant_type: "client_credentials", client_id: confidential.id, client_secret: secret }

    expect(response).to have_http_status(:bad_request)
    expect(JSON.parse(response.body)["error"]).to eq("unauthorized_client")
  end
end
