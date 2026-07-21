require "rails_helper"

RSpec.describe "Access auditing (AuditEvent)", type: :request do
  def create_patient
    post "/Patient", params: valid_patient_payload, as: :json
    JSON.parse(response.body)["id"]
  end

  describe "automatic recording" do
    it "audits a create with the new resource's id" do
      patient_id = create_patient

      record = AuditEvent.sole
      expect(record).to have_attributes(
        interaction: "create", action: "C",
        resource_type: "Patient", resource_id: patient_id,
        request_method: "POST", response_status: 201,
        client_id: nil, client_name: nil
      )
    end

    it "audits reads, searches, deletes, and operations with the right interaction codes" do
      patient_id = create_patient
      get "/Patient/#{patient_id}"
      get "/Patient?gender=male"
      get "/Patient/#{patient_id}/$everything"
      delete "/Patient/#{patient_id}"
      get "/_history"

      interactions = AuditEvent.order(:occurred_at).pluck(:interaction, :action)
      expect(interactions).to eq([
        %w[create C], %w[read R], %w[search-type E], %w[operation E], %w[delete D], %w[history-system R]
      ])

      search = AuditEvent.find_by(interaction: "search-type")
      expect(search.request_path).to eq("/Patient?gender=male")
      expect(search.resource_id).to be_nil
    end

    it "audits failures with a failure outcome" do
      get "/Patient/no-such-id"

      record = AuditEvent.sole
      expect(record.response_status).to eq(404)
      expect(record.to_fhir["outcome"]).to eq("4")
    end

    it "audits Bundle requests as transaction or batch" do
      post "/", params: { "resourceType" => "Bundle", "type" => "batch",
                          "entry" => [{ "request" => { "method" => "GET", "url" => "Patient/x" } }] }, as: :json

      expect(AuditEvent.sole.interaction).to eq("batch")
    end

    it "does not audit reads of the audit trail itself" do
      get "/AuditEvent"

      expect(AuditEvent.count).to eq(0)
    end

    context "with auth enabled" do
      around { |example| with_fhir_auth { example.run } }

      it "attributes authenticated requests to the client" do
        client, = OauthClient.register(name: "audited-client", scopes: "system/*.read")
        _record, token = AccessToken.issue(client, scopes: ["system/*.read"])

        get "/Patient", headers: bearer_header(token)

        record = AuditEvent.sole
        expect(record.client_id).to eq(client.id)
        expect(record.client_name).to eq("audited-client")
        expect(record.to_fhir["agent"].first.dig("who", "display")).to eq("audited-client")
      end

      it "audits denied requests: 401 as anonymous, 403 attributed to the client" do
        get "/Patient"
        expect(AuditEvent.order(:occurred_at).last).to have_attributes(response_status: 401, client_id: nil)

        client, = OauthClient.register(name: "readonly", scopes: "system/*.read")
        _record, token = AccessToken.issue(client, scopes: ["system/*.read"])
        post "/Patient", params: valid_patient_payload.to_json,
                         headers: bearer_header(token).merge("CONTENT_TYPE" => "application/json")

        denied = AuditEvent.order(:occurred_at).last
        expect(denied).to have_attributes(response_status: 403, client_id: client.id, interaction: "create")
      end
    end
  end

  describe "GET /AuditEvent (search)" do
    it "returns audit events as a searchset Bundle, newest first" do
      patient_id = create_patient
      get "/Patient/#{patient_id}"

      get "/AuditEvent"

      expect(response).to have_http_status(:ok)
      bundle = JSON.parse(response.body)
      expect(bundle["type"]).to eq("searchset")
      expect(bundle["total"]).to eq(2)

      newest = bundle["entry"].first["resource"]
      expect(newest["resourceType"]).to eq("AuditEvent")
      expect(newest["subtype"].first["code"]).to eq("read")
      expect(newest.dig("type", "code")).to eq("rest")
      expect(newest["entity"].first.dig("what", "reference")).to eq("Patient/#{patient_id}")
    end

    it "filters by entity-type, entity, subtype, and agent" do
      patient_id = create_patient
      post "/Observation", params: valid_observation_payload(subject_id: patient_id), as: :json

      get "/AuditEvent?entity-type=Observation"
      expect(JSON.parse(response.body)["total"]).to eq(1)

      get "/AuditEvent?entity=Patient/#{patient_id}"
      expect(JSON.parse(response.body)["total"]).to eq(1)

      get "/AuditEvent?subtype=create"
      expect(JSON.parse(response.body)["total"]).to eq(2)

      get "/AuditEvent?agent=no-such-client"
      expect(JSON.parse(response.body)["total"]).to eq(0)
    end

    it "filters by date range and rejects malformed dates" do
      create_patient
      cutoff = AuditEvent.sole.occurred_at

      get "/AuditEvent?date=ge#{Rack::Utils.escape((cutoff - 1.second).utc.iso8601)}"
      expect(JSON.parse(response.body)["total"]).to eq(1)

      get "/AuditEvent?date=le#{Rack::Utils.escape((cutoff - 1.second).utc.iso8601)}"
      expect(JSON.parse(response.body)["total"]).to eq(0)

      get "/AuditEvent?date=not-a-date"
      expect(response).to have_http_status(:bad_request)
    end

    it "pages with _count and navigation links" do
      3.times { create_patient }

      get "/AuditEvent?_count=2"

      bundle = JSON.parse(response.body)
      expect(bundle["entry"].size).to eq(2)
      links = bundle["link"].to_h { |l| [l["relation"], l["url"]] }
      expect(links["next"]).to include("_offset=2")

      get URI.parse(links.fetch("next")).request_uri
      expect(JSON.parse(response.body)["entry"].size).to eq(1)
    end
  end

  describe "GET /AuditEvent/:id" do
    it "reads a single audit event and 404s on unknown ids" do
      create_patient
      audit_id = AuditEvent.sole.id

      get "/AuditEvent/#{audit_id}"
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["id"]).to eq(audit_id)

      get "/AuditEvent/no-such-id"
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "immutability and access control" do
    it "exposes no write routes for AuditEvent" do
      # show_exceptions is off in test, so an unrouted request raises instead
      # of rendering the production 404.
      expect { post "/AuditEvent", params: { "resourceType" => "AuditEvent" }, as: :json }
        .to raise_error(ActionController::RoutingError)
    end

    it "requires an AuditEvent read scope when auth is enabled" do
      with_fhir_auth do
        patient_only = issue_access_token(scopes: "system/Patient.read")
        get "/AuditEvent", headers: bearer_header(patient_only)
        expect(response).to have_http_status(:forbidden)

        wildcard = issue_access_token(scopes: "system/*.read")
        get "/AuditEvent", headers: bearer_header(wildcard)
        expect(response).to have_http_status(:ok)
      end
    end
  end
end
