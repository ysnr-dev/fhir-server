require "rails_helper"

RSpec.describe "Admin launch contexts (/admin/launch_contexts)", type: :request do
  let(:admin_token) { "a" * 64 }
  let(:redirect_uri) { "https://app.example/cb" }

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
  let!(:practitioner_id) { create_resource("Practitioner", valid_practitioner_payload) }
  let!(:encounter_id) do
    create_resource("Encounter", valid_encounter_payload("subject" => { "reference" => "Patient/#{patient_id}" }))
  end
  let(:client) do
    OauthClient.register(name: "Karte App", scopes: "user/*.read launch", redirect_uris: redirect_uri,
                         client_type: "public").first
  end

  def mint(**overrides)
    body = { client_id: client.id, patient_id: patient_id, encounter_id: encounter_id,
             practitioner_id: practitioner_id }.merge(overrides)
    post "/admin/launch_contexts", params: body.to_json, headers: json_headers
    JSON.parse(response.body)
  end

  it "requires the admin token" do
    post "/admin/launch_contexts", params: {}.to_json, headers: { "CONTENT_TYPE" => "application/json" }

    expect(response).to have_http_status(:unauthorized)
  end

  it "issues a single-use launch token bound to the client and context" do
    expect { mint(need_patient_banner: true, issued_by: "fhir-client") }.to change(LaunchContext, :count).by(1)

    expect(response).to have_http_status(:created)
    body = JSON.parse(response.body)
    expect(body["launch"]).to match(/\A[0-9a-f]{64}\z/)
    expect(body["expires_in"]).to eq(300)
    expect(body.values_at("client_id", "patient_id", "encounter_id", "practitioner_id"))
      .to eq([client.id, patient_id, encounter_id, practitioner_id])

    context = LaunchContext.authenticate(body["launch"])
    expect(context.oauth_client_id).to eq(client.id)
    expect(context.need_patient_banner).to be(true)
    expect(context.issued_by).to eq("fhir-client")
    expect(context.used?).to be(false)
    expect(LaunchContext.where(token_digest: body["launch"])).to be_empty
  end

  it "works without an encounter" do
    body = mint(encounter_id: nil)

    expect(response).to have_http_status(:created)
    expect(body).not_to have_key("encounter_id")
  end

  it "returns 400 for malformed fields" do
    mint(client_id: 123)
    expect(response).to have_http_status(:bad_request)

    mint(need_patient_banner: "yes")
    expect(response).to have_http_status(:bad_request)

    mint(practitioner_id: nil)
    expect(response).to have_http_status(:bad_request)
    expect(JSON.parse(response.body)["error_description"]).to include("practitioner_id")
  end

  it "returns 404 for an unknown client" do
    mint(client_id: SecureRandom.uuid)

    expect(response).to have_http_status(:not_found)
  end

  it "returns 422 for a client not registered for EHR launch" do
    backend, = OauthClient.register(name: "backend", scopes: "system/*.read")
    plain, = OauthClient.register(name: "plain", scopes: "user/*.read", redirect_uris: redirect_uri)

    mint(client_id: backend.id)
    expect(response).to have_http_status(:unprocessable_content)
    expect(JSON.parse(response.body)["errors"].first).to include("launch")

    mint(client_id: plain.id)
    expect(response).to have_http_status(:unprocessable_content)
  end

  it "returns 422 when the patient, practitioner or encounter does not exist" do
    mint(patient_id: "nope")
    expect(JSON.parse(response.body)["errors"]).to include("patient_id does not exist")

    mint(practitioner_id: "nope")
    expect(JSON.parse(response.body)["errors"]).to include("practitioner_id does not exist")

    mint(encounter_id: "nope")
    expect(JSON.parse(response.body)["errors"]).to include("encounter_id does not exist")
  end

  it "returns 422 when the encounter belongs to another patient" do
    other = create_resource("Patient", valid_patient_payload)

    mint(patient_id: other)

    expect(response).to have_http_status(:unprocessable_content)
    expect(JSON.parse(response.body)["errors"]).to include("encounter_id does not belong to patient_id")
  end

  it "audits the issue without recording the token" do
    expect { mint }.to change(AuditEvent, :count).by(1)

    event = AuditEvent.order(:occurred_at).last
    expect(event.client_name).to eq("admin-api")
    expect(event.resource_type).to eq("LaunchContext")
    expect(event.resource_id).to eq(LaunchContext.last.id.to_s)
    expect(event.request_path).to eq("/admin/launch_contexts")
  end

  it "is deleted with its client" do
    mint
    expect { client.destroy! }.to change(LaunchContext, :count).by(-1)
  end
end
