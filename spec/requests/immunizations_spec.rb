require "rails_helper"

RSpec.describe "Immunizations", type: :request do
  def create_patient
    post "/Patient", params: valid_patient_payload, as: :json
    JSON.parse(response.body)["id"]
  end

  describe "POST /Immunization" do
    it "creates and returns 201 with Location, ETag, and meta" do
      patient_id = create_patient

      post "/Immunization", params: valid_immunization_payload(patient_id: patient_id), as: :json

      expect(response).to have_http_status(:created)
      expect(response.content_type).to include("application/fhir+json")
      expect(response.headers["Location"]).to match(%r{/Immunization/[\w-]+/_history/1\z})
      expect(response.headers["ETag"]).to eq('W/"1"')

      body = JSON.parse(response.body)
      expect(body["resourceType"]).to eq("Immunization")
      expect(body["meta"]["profile"]).to eq(["http://jpfhir.jp/fhir/core/StructureDefinition/JP_Immunization"])
    end

    it "returns 422 when vaccineCode is missing" do
      patient_id = create_patient

      post "/Immunization", params: valid_immunization_payload(patient_id: patient_id).except("vaccineCode"), as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "returns 422 for an invalid status" do
      patient_id = create_patient

      post "/Immunization", params: valid_immunization_payload(patient_id: patient_id, status: "bogus"), as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "returns 422 when patient references a non-existent patient" do
      post "/Immunization", params: valid_immunization_payload(patient_id: "does-not-exist"), as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "GET /Immunization/:id" do
    it "returns the resource" do
      patient_id = create_patient
      post "/Immunization", params: valid_immunization_payload(patient_id: patient_id), as: :json
      id = JSON.parse(response.body)["id"]

      get "/Immunization/#{id}"

      expect(response).to have_http_status(:ok)
    end

    it "returns 404 for an unknown id" do
      get "/Immunization/does-not-exist"

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "PUT and DELETE" do
    it "updates and then deletes" do
      patient_id = create_patient
      post "/Immunization", params: valid_immunization_payload(patient_id: patient_id), as: :json
      id = JSON.parse(response.body)["id"]

      put "/Immunization/#{id}", params: valid_immunization_payload(patient_id: patient_id, lotNumber: "LOT-999"), as: :json
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["meta"]["versionId"]).to eq("2")

      delete "/Immunization/#{id}"
      expect(response).to have_http_status(:no_content)

      get "/Immunization/#{id}"
      expect(response).to have_http_status(:gone)
    end
  end

  describe "GET /Immunization (search)" do
    it "finds by patient reference" do
      patient_id = create_patient
      post "/Immunization", params: valid_immunization_payload(patient_id: patient_id), as: :json

      get "/Immunization", params: { patient: "Patient/#{patient_id}" }

      bundle = JSON.parse(response.body)
      expect(bundle["type"]).to eq("searchset")
      expect(bundle["total"]).to eq(1)
    end

    it "finds by vaccine-code" do
      patient_id = create_patient
      post "/Immunization", params: valid_immunization_payload(patient_id: patient_id), as: :json

      get "/Immunization", params: { "vaccine-code" => "49281-0215-88" }

      expect(JSON.parse(response.body)["total"]).to be >= 1
    end

    it "includes the referenced Patient via Immunization:patient" do
      patient_id = create_patient
      post "/Immunization", params: valid_immunization_payload(patient_id: patient_id), as: :json
      id = JSON.parse(response.body)["id"]

      get "/Immunization", params: { _id: id, _include: "Immunization:patient" }

      bundle = JSON.parse(response.body)
      included = bundle["entry"].select { |entry| entry.dig("search", "mode") == "include" }
      expect(included.map { |entry| entry["resource"]["resourceType"] }).to eq(["Patient"])
    end
  end
end
