require "rails_helper"

RSpec.describe "POST _search and patient compartment search", type: :request do
  let(:form) { { "CONTENT_TYPE" => "application/x-www-form-urlencoded" } }

  def create_patient(overrides = {})
    post "/Patient", params: valid_patient_payload(overrides), as: :json
    JSON.parse(response.body)["id"]
  end

  def create_observation(patient_id, overrides = {})
    post "/Observation", params: valid_observation_payload(subject_id: patient_id, **overrides), as: :json
    JSON.parse(response.body)["id"]
  end

  def bundle
    JSON.parse(response.body)
  end

  def match_ids
    bundle.fetch("entry", []).select { |e| e.dig("search", "mode") == "match" }.map { |e| e.dig("resource", "id") }
  end

  describe "POST /{type}/_search" do
    it "searches with the parameters in a form-encoded body" do
      yamada = create_patient
      create_patient("name" => [{ "use" => "official", "family" => "佐藤", "given" => ["次郎"] }])

      post "/Patient/_search", params: "family=#{Rack::Utils.escape('山田')}", headers: form

      expect(response).to have_http_status(:ok)
      expect(bundle["type"]).to eq("searchset")
      expect(match_ids).to eq([yamada])
    end

    it "keeps repeated parameters (AND) and comma values (OR) from the body" do
      patient_id = create_patient
      other_id = create_patient
      mine = create_observation(patient_id)
      create_observation(other_id)

      post "/Observation/_search",
           params: "subject=Patient/#{patient_id},Patient/#{other_id}&subject=Patient/#{patient_id}", headers: form

      expect(match_ids).to eq([mine])
    end

    it "combines URL and body parameters" do
      patient_id = create_patient
      other_id = create_patient
      mine = create_observation(patient_id)
      create_observation(other_id)

      post "/Observation/_search?subject=Patient/#{patient_id}", params: "_count=1", headers: form

      expect(bundle["total"]).to eq(1)
      expect(match_ids).to eq([mine])
    end

    it "returns everything for an empty body" do
      create_patient

      post "/Patient/_search"

      expect(response).to have_http_status(:ok)
      expect(bundle["total"]).to eq(1)
    end

    it "rejects a body that is not form-encoded with 415" do
      post "/Patient/_search", params: { family: "山田" }.to_json, headers: { "CONTENT_TYPE" => "application/json" }

      expect(response).to have_http_status(:unsupported_media_type)
      expect(bundle["resourceType"]).to eq("OperationOutcome")
    end

    it "honors Prefer: handling=strict" do
      post "/Patient/_search", params: "no-such-param=1", headers: form.merge("Prefer" => "handling=strict")

      expect(response).to have_http_status(:bad_request)
    end

    it "is audited as a search without the criteria in the request path" do
      create_patient

      post "/Patient/_search", params: "family=#{Rack::Utils.escape('山田')}", headers: form

      event = AuditEvent.order(:occurred_at).last
      expect(event.interaction).to eq("search-type")
      expect(event.request_path).to eq("/Patient/_search")
    end

    it "needs only the read scope" do
      with_fhir_auth do
        post "/Patient/_search", params: "family=x", headers: form.merge(bearer_header(issue_access_token(scopes: "system/Patient.read")))
        expect(response).to have_http_status(:ok)

        post "/Patient/_search", params: "family=x", headers: form.merge(bearer_header(issue_access_token(scopes: "system/Observation.read")))
        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe "GET /Patient/:id/{type}" do
    let!(:mine) { create_patient }
    let!(:theirs) { create_patient }
    let!(:my_observation) { create_observation(mine) }
    let!(:their_observation) { create_observation(theirs) }

    it "returns only that patient's resources" do
      get "/Patient/#{mine}/Observation"

      expect(response).to have_http_status(:ok)
      expect(bundle["total"]).to eq(1)
      expect(match_ids).to eq([my_observation])
    end

    it "applies ordinary search parameters on top" do
      get "/Patient/#{mine}/Observation?_id=#{their_observation}"
      expect(bundle["total"]).to eq(0)

      get "/Patient/#{mine}/Observation?_id=#{my_observation}&_include=Observation:subject"
      expect(match_ids).to eq([my_observation])
      included = bundle["entry"].select { |e| e.dig("search", "mode") == "include" }
      expect(included.map { |e| e.dig("resource", "id") }).to eq([mine])
    end

    it "pages within the compartment path" do
      2.times { create_observation(mine) }

      get "/Patient/#{mine}/Observation?_count=2"

      next_link = bundle["link"].find { |l| l["relation"] == "next" }
      expect(URI.parse(next_link["url"]).path).to eq("/Patient/#{mine}/Observation")

      get URI.parse(next_link["url"]).request_uri
      expect(bundle["entry"].size).to eq(1)
      expect(bundle["total"]).to eq(3)
    end

    it "supports POST _search, ignoring a patient_id field in the body" do
      post "/Patient/#{mine}/Observation/_search", params: "_id=#{my_observation}&patient_id=#{theirs}", headers: form
      expect(match_ids).to eq([my_observation])

      post "/Observation/_search", params: "patient_id=#{mine}", headers: form
      expect(bundle["total"]).to eq(2)
    end

    it "is 404 for an unknown patient and 410 for a deleted one" do
      get "/Patient/no-such-patient/Observation"
      expect(response).to have_http_status(:not_found)

      delete "/Patient/#{theirs}"
      get "/Patient/#{theirs}/Observation"
      expect(response).to have_http_status(:gone)
    end

    it "is 400 for a type outside the Patient compartment" do
      get "/Patient/#{mine}/Medication"

      expect(response).to have_http_status(:bad_request)
      expect(bundle.dig("issue", 0, "code")).to eq("not-supported")
    end

    it "confines a patient-context token to its own compartment" do
      with_fhir_auth do
        headers = bearer_header(issue_patient_token(patient_id: mine))

        get "/Patient/#{mine}/Observation", headers: headers
        expect(match_ids).to eq([my_observation])

        get "/Patient/#{theirs}/Observation", headers: headers
        expect(response).to have_http_status(:not_found)
      end
    end

    it "requires the read scope of the searched type" do
      with_fhir_auth do
        get "/Patient/#{mine}/Observation", headers: bearer_header(issue_access_token(scopes: "system/Patient.read"))
        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  it "advertises the Patient compartment in the CapabilityStatement" do
    get "/metadata"

    expect(bundle.dig("rest", 0, "compartment")).to eq(["http://hl7.org/fhir/CompartmentDefinition/patient"])
  end
end
