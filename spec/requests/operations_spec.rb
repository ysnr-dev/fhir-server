require "rails_helper"

RSpec.describe "FHIR operations ($validate, Patient/$everything)", type: :request do
  def create_patient(overrides = {})
    post "/Patient", params: valid_patient_payload(overrides), as: :json
    JSON.parse(response.body)["id"]
  end

  describe "POST /{type}/$validate" do
    it "returns 200 with an informational outcome for a valid resource, without persisting" do
      post "/Patient/$validate", params: valid_patient_payload, as: :json

      expect(response).to have_http_status(:ok)
      outcome = JSON.parse(response.body)
      expect(outcome["resourceType"]).to eq("OperationOutcome")
      expect(outcome["issue"].first["severity"]).to eq("information")
      expect(Patient.count).to eq(0)
    end

    it "returns 200 with error issues for an invalid resource" do
      post "/Observation/$validate", params: { "resourceType" => "Observation" }, as: :json

      expect(response).to have_http_status(:ok)
      issues = JSON.parse(response.body)["issue"]
      expect(issues.map { |i| i["severity"] }).to all(eq("error"))
      expect(Observation.count).to eq(0)
    end

    it "reports a resourceType mismatch as a validation error" do
      post "/Patient/$validate", params: { "resourceType" => "Observation", "status" => "final" }, as: :json

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["issue"].first["code"]).to eq("invalid")
    end

    it "accepts a Parameters-wrapped resource" do
      wrapped = {
        "resourceType" => "Parameters",
        "parameter" => [{ "name" => "resource", "resource" => valid_patient_payload }]
      }

      post "/Patient/$validate", params: wrapped, as: :json

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["issue"].first["severity"]).to eq("information")
    end

    it "returns 400 for Parameters without a resource parameter" do
      post "/Patient/$validate", params: { "resourceType" => "Parameters", "parameter" => [] }, as: :json

      expect(response).to have_http_status(:bad_request)
    end

    it "returns 400 for a malformed body" do
      post "/Patient/$validate", params: "not-json", headers: { "CONTENT_TYPE" => "application/json" }

      expect(response).to have_http_status(:bad_request)
    end
  end

  describe "GET /Patient/:id/$everything" do
    it "returns the patient plus every compartment resource, excluding other patients' data" do
      patient_id = create_patient
      other_id = create_patient

      post "/Observation", params: valid_observation_payload(subject_id: patient_id), as: :json
      obs_id = JSON.parse(response.body)["id"]
      post "/Condition", params: valid_condition_payload(subject_id: patient_id), as: :json
      post "/MedicationRequest", params: valid_medication_request_payload(subject_id: patient_id), as: :json
      post "/AllergyIntolerance", params: valid_allergy_intolerance_payload(patient_id: patient_id), as: :json
      post "/Observation", params: valid_observation_payload(subject_id: other_id), as: :json

      get "/Patient/#{patient_id}/$everything"

      expect(response).to have_http_status(:ok)
      bundle = JSON.parse(response.body)
      expect(bundle["resourceType"]).to eq("Bundle")
      expect(bundle["type"]).to eq("searchset")
      expect(bundle["total"]).to eq(5)

      types = bundle["entry"].map { |e| e.dig("resource", "resourceType") }
      expect(types).to contain_exactly("Patient", "Observation", "Condition", "MedicationRequest", "AllergyIntolerance")
      expect(bundle["entry"].first.dig("resource", "id")).to eq(patient_id)

      obs_entry = bundle["entry"].find { |e| e.dig("resource", "resourceType") == "Observation" }
      expect(obs_entry.dig("resource", "id")).to eq(obs_id)
      expect(obs_entry["fullUrl"]).to include("/Observation/#{obs_id}")
    end

    it "excludes soft-deleted compartment resources" do
      patient_id = create_patient
      post "/Observation", params: valid_observation_payload(subject_id: patient_id), as: :json
      obs_id = JSON.parse(response.body)["id"]
      delete "/Observation/#{obs_id}"

      get "/Patient/#{patient_id}/$everything"

      expect(JSON.parse(response.body)["total"]).to eq(1)
    end

    it "filters compartment resources with _type while keeping the patient" do
      patient_id = create_patient
      post "/Observation", params: valid_observation_payload(subject_id: patient_id), as: :json
      post "/Condition", params: valid_condition_payload(subject_id: patient_id), as: :json

      get "/Patient/#{patient_id}/$everything?_type=Observation"

      types = JSON.parse(response.body)["entry"].map { |e| e.dig("resource", "resourceType") }
      expect(types).to contain_exactly("Patient", "Observation")
    end

    it "returns 400 for an unknown _type" do
      patient_id = create_patient

      get "/Patient/#{patient_id}/$everything?_type=Bogus"

      expect(response).to have_http_status(:bad_request)
      expect(JSON.parse(response.body)["issue"].first["diagnostics"]).to include("Bogus")
    end

    it "filters everything (including the patient) with _since" do
      patient_id = create_patient
      cutoff = ResourceVersion.find_by(resource_id: patient_id).last_updated + 0.001
      post "/Observation", params: valid_observation_payload(subject_id: patient_id), as: :json

      get "/Patient/#{patient_id}/$everything?_since=#{Rack::Utils.escape(cutoff.utc.iso8601(6))}"

      types = JSON.parse(response.body)["entry"].map { |e| e.dig("resource", "resourceType") }
      expect(types).to contain_exactly("Observation")
    end

    it "returns 400 for an unparseable _since" do
      patient_id = create_patient

      get "/Patient/#{patient_id}/$everything?_since=not-a-date"

      expect(response).to have_http_status(:bad_request)
    end

    it "returns 404 for an unknown patient and 410 for a deleted one" do
      get "/Patient/no-such-id/$everything"
      expect(response).to have_http_status(:not_found)

      patient_id = create_patient
      delete "/Patient/#{patient_id}"
      get "/Patient/#{patient_id}/$everything"
      expect(response).to have_http_status(:gone)
    end
  end
end
