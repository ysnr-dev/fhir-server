require "rails_helper"

RSpec.describe "Admin OAuth clients (/admin/oauth_clients)", type: :request do
  let(:admin_token) { "a" * 64 }
  let(:redirect_uri) { "https://app.example/cb" }

  around do |example|
    previous = ENV["FHIR_ADMIN_TOKEN"]
    ENV["FHIR_ADMIN_TOKEN"] = admin_token
    example.run
  ensure
    ENV["FHIR_ADMIN_TOKEN"] = previous
  end

  def admin_headers
    { "X-FHIR-Admin-Token" => admin_token }
  end

  def json_headers
    admin_headers.merge("CONTENT_TYPE" => "application/json")
  end

  def create_client(payload)
    post "/admin/oauth_clients", params: payload.to_json, headers: json_headers
    JSON.parse(response.body)
  end

  describe "authentication" do
    it "rejects every action without a token" do
      get "/admin/oauth_clients"
      expect(response).to have_http_status(:unauthorized)

      post "/admin/oauth_clients", params: {}.to_json, headers: { "CONTENT_TYPE" => "application/json" }
      expect(response).to have_http_status(:unauthorized)

      delete "/admin/oauth_clients/#{SecureRandom.uuid}"
      expect(response).to have_http_status(:unauthorized)
    end

    it "fails closed whether or not FHIR auth is enabled" do
      with_fhir_auth { get "/admin/oauth_clients" }

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "POST /admin/oauth_clients" do
    it "registers a backend client and returns the secret exactly once" do
      body = create_client(name: "my-mcp-server", scopes: ["system/Patient.read", "system/Observation.read"])

      expect(response).to have_http_status(:created)
      expect(response.headers["Cache-Control"]).to include("no-store")
      expect(body["client_secret"]).to be_present
      expect(body["kind"]).to eq("backend")
      expect(body["auth_method"]).to eq("client_secret")
      expect(body["client_type"]).to eq("confidential")
      expect(body["scopes"]).to eq(["system/Patient.read", "system/Observation.read"])
      expect(body["redirect_uris"]).to eq([])

      # 返ってきた資格情報が本当に使えることを確認する
      expect(OauthClient.authenticate(body["client_id"], body["client_secret"])).to be_present
    end

    it "registers a JWKS client with no secret" do
      jwks = { "keys" => [{ "kty" => "RSA", "n" => "x", "e" => "AQAB" }] }
      body = create_client(name: "jwks-client", scopes: ["system/*.read"], jwks: jwks)

      expect(response).to have_http_status(:created)
      expect(body).not_to have_key("client_secret")
      expect(body["auth_method"]).to eq("private_key_jwt")
      expect(body["jwks_key_count"]).to eq(1)
    end

    it "registers a public launch client with no secret" do
      body = create_client(
        name: "my-spa", scopes: ["patient/*.read", "offline_access"],
        redirect_uris: [redirect_uri], client_type: "public"
      )

      expect(response).to have_http_status(:created)
      expect(body).not_to have_key("client_secret")
      expect(body["kind"]).to eq("launch")
      expect(body["auth_method"]).to eq("none")
      expect(body["redirect_uris"]).to eq([redirect_uri])
    end

    it "issues a secret for a confidential launch client" do
      body = create_client(
        name: "server-side-app", scopes: ["patient/*.read"],
        redirect_uris: [redirect_uri], client_type: "confidential"
      )

      expect(body["client_secret"]).to be_present
      expect(body["auth_method"]).to eq("client_secret")
    end

    it "accepts scopes as a space-separated string" do
      body = create_client(name: "string-scopes", scopes: "system/Patient.read system/Observation.read")

      expect(response).to have_http_status(:created)
      expect(body["scopes"]).to eq(["system/Patient.read", "system/Observation.read"])
    end

    describe "400 for a malformed request shape" do
      it "rejects non-string scopes" do
        create_client(name: "x", scopes: [{ "system" => "Patient" }])

        expect(response).to have_http_status(:bad_request)
        expect(JSON.parse(response.body)["error"]).to eq("invalid_request")
      end

      it "rejects non-string redirect_uris" do
        create_client(name: "x", scopes: ["patient/*.read"], redirect_uris: [1, 2])

        expect(response).to have_http_status(:bad_request)
      end

      it "rejects a JWKS without a keys array" do
        create_client(name: "x", scopes: ["system/*.read"], jwks: { "kty" => "RSA" })

        expect(response).to have_http_status(:bad_request)
        expect(JSON.parse(response.body)["error_description"]).to include("keys")
      end

      it "rejects malformed JSON" do
        post "/admin/oauth_clients", params: "{not json", headers: json_headers

        expect(response).to have_http_status(:bad_request)
        expect(JSON.parse(response.body)["error_description"]).to include("Malformed JSON")
      end
    end

    describe "422 for a semantically invalid registration" do
      it "rejects a missing name" do
        create_client(scopes: ["system/*.read"])

        expect(response).to have_http_status(:unprocessable_content)
        expect(JSON.parse(response.body)["errors"].join).to match(/name/i)
      end

      it "rejects missing scopes" do
        create_client(name: "no-scopes")

        expect(response).to have_http_status(:unprocessable_content)
        expect(JSON.parse(response.body)["errors"].join).to match(/scopes/i)
      end

      it "rejects an unsupported scope" do
        create_client(name: "x", scopes: ["user/*.read"])

        expect(response).to have_http_status(:unprocessable_content)
      end

      it "rejects mixing system/ and patient/ scopes" do
        create_client(name: "x", scopes: ["system/*.read", "patient/*.read"], redirect_uris: [redirect_uri])

        expect(response).to have_http_status(:unprocessable_content)
        expect(JSON.parse(response.body)["errors"].join).to match(/mix/)
      end

      it "rejects a patient/ write scope" do
        create_client(name: "x", scopes: ["patient/Observation.write"], redirect_uris: [redirect_uri])

        expect(response).to have_http_status(:unprocessable_content)
      end

      it "rejects patient/ scopes without redirect_uris" do
        create_client(name: "x", scopes: ["patient/*.read"])

        expect(response).to have_http_status(:unprocessable_content)
      end

      it "rejects a JWKS on a public client" do
        create_client(name: "x", scopes: ["patient/*.read"], redirect_uris: [redirect_uri],
                      client_type: "public", jwks: { "keys" => [] })

        expect(response).to have_http_status(:unprocessable_content)
      end

      it "rejects a relative redirect_uri" do
        create_client(name: "x", scopes: ["patient/*.read"], redirect_uris: ["/callback"])

        expect(response).to have_http_status(:unprocessable_content)
        expect(JSON.parse(response.body)["errors"].join).to include("absolute")
      end
    end

    it "records a create audit event attributed to the admin API" do
      expect { create_client(name: "audited", scopes: ["system/*.read"]) }
        .to change(AuditEvent, :count).by(1)

      event = AuditEvent.order(:occurred_at).last
      expect(event.action).to eq("C")
      expect(event.interaction).to eq("create")
      expect(event.client_name).to eq("admin-api")
      expect(event.client_id).to be_nil
      expect(event.resource_type).to eq("OauthClient")
      expect(event.resource_id).to be_present
    end
  end

  describe "GET /admin/oauth_clients" do
    it "never exposes a secret" do
      created = create_client(name: "leak-check", scopes: ["system/*.read"])
      secret = created.fetch("client_secret")

      get "/admin/oauth_clients", headers: admin_headers

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include(secret)
      expect(response.body).not_to include("secret_digest")

      item = JSON.parse(response.body)["items"].first
      expect(item).not_to have_key("client_secret")
      expect(item["auth_method"]).to eq("client_secret")
    end

    it "reports active token counts without an N+1" do
      created = create_client(name: "counted", scopes: ["system/*.read"])
      client = OauthClient.find(created["client_id"])
      AccessToken.issue(client, scopes: ["system/*.read"])
      expired, = AccessToken.issue(client, scopes: ["system/*.read"])
      expired.update!(expires_at: 1.hour.ago)
      revoked, = AccessToken.issue(client, scopes: ["system/*.read"])
      revoked.update!(revoked_at: Time.current)

      get "/admin/oauth_clients", headers: admin_headers

      item = JSON.parse(response.body)["items"].find { |i| i["client_id"] == client.id }
      expect(item["active_access_token_count"]).to eq(1)
      expect(item["active_refresh_token_count"]).to eq(0)
    end

    it "returns the newest client first" do
      create_client(name: "older", scopes: ["system/*.read"])
      create_client(name: "newer", scopes: ["system/*.read"])

      get "/admin/oauth_clients", headers: admin_headers

      body = JSON.parse(response.body)
      expect(body["total"]).to eq(2)
      expect(body["items"].first["name"]).to eq("newer")
    end
  end

  describe "DELETE /admin/oauth_clients/:id" do
    let(:client) do
      OauthClient.register(
        name: "doomed", scopes: "patient/*.read offline_access",
        redirect_uris: redirect_uri, client_type: "public"
      ).first
    end
    let(:patient) do
      Patient.create!(id: SecureRandom.uuid, content: { "resourceType" => "Patient" },
                      version_id: 1, last_updated: Time.current)
    end
    let(:user) { register_user(patient_id: patient.id) }
    let(:code) do
      AuthorizationCode.issue(
        client: client, user: user, scopes: %w[patient/*.read offline_access],
        redirect_uri: redirect_uri, code_challenge: "c" * 43
      ).first
    end

    it "deletes the client and reports what it took with it" do
      AccessToken.issue(client, scopes: %w[patient/*.read], user: user,
                                patient_id: user.patient_id, authorization_code: code)
      _refresh, raw_refresh = RefreshToken.issue(
        client: client, user: user, patient_id: user.patient_id,
        scopes: %w[patient/*.read offline_access], authorization_code: code
      )

      delete "/admin/oauth_clients/#{client.id}", headers: admin_headers

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["client_id"]).to eq(client.id)
      expect(body["deleted"]).to include(
        "access_tokens" => 1, "refresh_tokens" => 1, "authorization_codes" => 1
      )

      expect(OauthClient.find_by(id: client.id)).to be_nil
      # 孤児のリフレッシュトークンを残さない(残すと refresh 要求が 500 になる)
      expect(RefreshToken.where(oauth_client_id: client.id)).to be_empty
      expect(RefreshToken.authenticate(raw_refresh)).to be_nil
    end

    it "detaches bulk exports instead of deleting the history" do
      export = BulkExport.create!(
        id: SecureRandom.uuid, kind: "system", output_format: "application/fhir+ndjson",
        request_url: "http://localhost/$export", oauth_client_id: client.id
      )

      delete "/admin/oauth_clients/#{client.id}", headers: admin_headers

      expect(JSON.parse(response.body)["deleted"]["bulk_exports_detached"]).to eq(1)
      expect(export.reload.oauth_client_id).to be_nil
    end

    it "returns 404 for an unknown id" do
      delete "/admin/oauth_clients/#{SecureRandom.uuid}", headers: admin_headers

      expect(response).to have_http_status(:not_found)
      expect(JSON.parse(response.body)["error"]).to eq("not_found")
    end

    it "records a delete audit event" do
      client_id = client.id

      expect { delete "/admin/oauth_clients/#{client_id}", headers: admin_headers }
        .to change(AuditEvent, :count).by(1)

      event = AuditEvent.order(:occurred_at).last
      expect(event.action).to eq("D")
      expect(event.client_name).to eq("admin-api")
      expect(event.resource_id).to eq(client_id)
      # OauthClient は FHIR のリソース型ではないので参照ではなく識別子で表す
      expect(event.to_fhir["entity"].first["what"]).to eq(
        "identifier" => { "value" => client_id }, "display" => "OauthClient"
      )
    end
  end
end
