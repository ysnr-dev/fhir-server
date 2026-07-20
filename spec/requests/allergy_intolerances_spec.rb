require "rails_helper"

RSpec.describe "AllergyIntolerances", type: :request do
  def create_patient
    post "/Patient", params: valid_patient_payload, as: :json
    JSON.parse(response.body)["id"]
  end

  describe "POST /AllergyIntolerance" do
    it "creates and returns 201 with Location, ETag, and meta" do
      patient_id = create_patient

      post "/AllergyIntolerance", params: valid_allergy_intolerance_payload(patient_id: patient_id), as: :json

      expect(response).to have_http_status(:created)
      expect(response.content_type).to include("application/fhir+json")
      expect(response.headers["Location"]).to match(%r{/AllergyIntolerance/[\w-]+/_history/1\z})
      expect(response.headers["ETag"]).to eq('W/"1"')

      body = JSON.parse(response.body)
      expect(body["resourceType"]).to eq("AllergyIntolerance")
      expect(body["meta"]["profile"]).to eq(["http://jpfhir.jp/fhir/core/StructureDefinition/JP_AllergyIntolerance"])
    end

    it "returns 422 for an invalid criticality" do
      patient_id = create_patient

      post "/AllergyIntolerance",
           params: valid_allergy_intolerance_payload(patient_id: patient_id, criticality: "bogus"), as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "returns 422 when patient references a non-existent patient" do
      post "/AllergyIntolerance", params: valid_allergy_intolerance_payload(patient_id: "does-not-exist"), as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "GET /AllergyIntolerance/:id" do
    it "returns the resource" do
      patient_id = create_patient
      post "/AllergyIntolerance", params: valid_allergy_intolerance_payload(patient_id: patient_id), as: :json
      id = JSON.parse(response.body)["id"]

      get "/AllergyIntolerance/#{id}"

      expect(response).to have_http_status(:ok)
    end

    it "returns 404 for an unknown id" do
      get "/AllergyIntolerance/does-not-exist"

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "PUT and DELETE" do
    it "updates and then deletes" do
      patient_id = create_patient
      post "/AllergyIntolerance", params: valid_allergy_intolerance_payload(patient_id: patient_id), as: :json
      id = JSON.parse(response.body)["id"]

      put "/AllergyIntolerance/#{id}",
          params: valid_allergy_intolerance_payload(patient_id: patient_id, criticality: "low"), as: :json
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["meta"]["versionId"]).to eq("2")

      delete "/AllergyIntolerance/#{id}"
      expect(response).to have_http_status(:no_content)

      get "/AllergyIntolerance/#{id}"
      expect(response).to have_http_status(:gone)
    end
  end

  describe "GET /AllergyIntolerance (search)" do
    it "finds by patient reference" do
      patient_id = create_patient
      post "/AllergyIntolerance", params: valid_allergy_intolerance_payload(patient_id: patient_id), as: :json

      get "/AllergyIntolerance", params: { patient: "Patient/#{patient_id}" }

      bundle = JSON.parse(response.body)
      expect(bundle["type"]).to eq("searchset")
      expect(bundle["total"]).to eq(1)
    end

    it "finds by category" do
      patient_id = create_patient
      post "/AllergyIntolerance", params: valid_allergy_intolerance_payload(patient_id: patient_id), as: :json

      get "/AllergyIntolerance", params: { category: "medication" }

      expect(JSON.parse(response.body)["total"]).to be >= 1
    end

    it "includes the referenced Patient via AllergyIntolerance:patient" do
      patient_id = create_patient
      post "/AllergyIntolerance", params: valid_allergy_intolerance_payload(patient_id: patient_id), as: :json
      id = JSON.parse(response.body)["id"]

      get "/AllergyIntolerance", params: { _id: id, _include: "AllergyIntolerance:patient" }

      bundle = JSON.parse(response.body)
      included = bundle["entry"].select { |entry| entry.dig("search", "mode") == "include" }
      expect(included.map { |entry| entry["resource"]["resourceType"] }).to eq(["Patient"])
    end
  end
end
