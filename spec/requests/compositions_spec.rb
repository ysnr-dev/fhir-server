require "rails_helper"

RSpec.describe "Composition", type: :request do
  def create_patient
    post "/Patient", params: valid_patient_payload, as: :json
    JSON.parse(response.body)["id"]
  end

  describe "create" do
    it "creates a valid composition with 201" do
      patient_id = create_patient

      post "/Composition", params: valid_composition_payload(subject_id: patient_id), as: :json

      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      expect(body["meta"]["versionId"]).to eq("1")
      expect(body["meta"]["profile"]).to eq(["http://hl7.org/fhir/StructureDefinition/Composition"])
    end

    it "returns 422 when status is missing or invalid" do
      patient_id = create_patient

      post "/Composition", params: valid_composition_payload(subject_id: patient_id).except("status"), as: :json
      expect(response).to have_http_status(:unprocessable_content)

      post "/Composition", params: valid_composition_payload(subject_id: patient_id, status: "draft"), as: :json
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "returns 422 when author is missing" do
      patient_id = create_patient

      post "/Composition", params: valid_composition_payload(subject_id: patient_id).except("author"), as: :json
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "returns 422 when the subject references a non-existent Patient" do
      post "/Composition", params: valid_composition_payload(subject_id: "does-not-exist"), as: :json
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "read / update / delete lifecycle" do
    it "supports the full instance lifecycle" do
      patient_id = create_patient
      post "/Composition", params: valid_composition_payload(subject_id: patient_id), as: :json
      id = JSON.parse(response.body)["id"]

      get "/Composition/#{id}"
      expect(response).to have_http_status(:ok)

      put "/Composition/#{id}", params: valid_composition_payload(subject_id: patient_id, status: "amended"), as: :json
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["meta"]["versionId"]).to eq("2")

      delete "/Composition/#{id}"
      expect(response).to have_http_status(:no_content)

      get "/Composition/#{id}"
      expect(response).to have_http_status(:gone)
    end
  end

  describe "search" do
    it "finds compositions by patient, status, type, category, and date" do
      patient_id = create_patient
      other_id = create_patient
      post "/Composition", params: valid_composition_payload(subject_id: patient_id), as: :json
      post "/Composition", params: valid_composition_payload(subject_id: other_id, status: "preliminary"), as: :json

      get "/Composition?patient=#{patient_id}"
      expect(JSON.parse(response.body)["total"]).to eq(1)

      get "/Composition?status=final"
      expect(JSON.parse(response.body)["total"]).to eq(1)

      get "/Composition?type=18842-5"
      expect(JSON.parse(response.body)["total"]).to eq(2)

      get "/Composition?category=11488-4"
      expect(JSON.parse(response.body)["total"]).to eq(2)

      get "/Composition?date=ge2026-07-01&date=le2026-08-01"
      expect(JSON.parse(response.body)["total"]).to eq(2)
    end

    it "finds compositions by identifier" do
      patient_id = create_patient
      post "/Composition", params: valid_composition_payload(subject_id: patient_id), as: :json

      get "/Composition?identifier=http://example.org/composition|COMP1"
      expect(JSON.parse(response.body)["total"]).to eq(1)
    end
  end

  it "joins the patient compartment ($everything)" do
    patient_id = create_patient
    post "/Composition", params: valid_composition_payload(subject_id: patient_id), as: :json

    get "/Patient/#{patient_id}/$everything"

    types = JSON.parse(response.body)["entry"].map { |e| e.dig("resource", "resourceType") }
    expect(types).to contain_exactly("Patient", "Composition")
  end
end
