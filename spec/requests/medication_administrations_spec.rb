require "rails_helper"

RSpec.describe "MedicationAdministrations", type: :request do
  def create_patient
    post "/Patient", params: valid_patient_payload, as: :json
    JSON.parse(response.body)["id"]
  end

  describe "POST /MedicationAdministration" do
    it "creates and returns 201 with Location, ETag, and meta" do
      subject_id = create_patient

      post "/MedicationAdministration", params: valid_medication_administration_payload(subject_id: subject_id), as: :json

      expect(response).to have_http_status(:created)
      expect(response.headers["Location"]).to match(%r{/MedicationAdministration/[\w-]+/_history/1\z})
      expect(response.headers["ETag"]).to eq('W/"1"')

      body = JSON.parse(response.body)
      expect(body["resourceType"]).to eq("MedicationAdministration")
      expect(body["meta"]["profile"]).to eq(["http://jpfhir.jp/fhir/core/StructureDefinition/JP_MedicationAdministration"])
    end

    it "returns 422 when status is missing" do
      subject_id = create_patient

      post "/MedicationAdministration",
           params: valid_medication_administration_payload(subject_id: subject_id).except("status"), as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "returns 422 when medication[x] is missing" do
      subject_id = create_patient

      post "/MedicationAdministration",
           params: valid_medication_administration_payload(subject_id: subject_id).except("medicationCodeableConcept"), as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "returns 422 when subject references a non-existent patient" do
      post "/MedicationAdministration",
           params: valid_medication_administration_payload(subject_id: "does-not-exist"), as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "GET /MedicationAdministration/:id" do
    it "returns the resource" do
      subject_id = create_patient
      post "/MedicationAdministration", params: valid_medication_administration_payload(subject_id: subject_id), as: :json
      id = JSON.parse(response.body)["id"]

      get "/MedicationAdministration/#{id}"

      expect(response).to have_http_status(:ok)
    end

    it "returns 404 for an unknown id" do
      get "/MedicationAdministration/does-not-exist"

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "PUT and DELETE" do
    it "updates and then deletes" do
      subject_id = create_patient
      post "/MedicationAdministration", params: valid_medication_administration_payload(subject_id: subject_id), as: :json
      id = JSON.parse(response.body)["id"]

      put "/MedicationAdministration/#{id}",
          params: valid_medication_administration_payload(subject_id: subject_id, status: "stopped"), as: :json
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["meta"]["versionId"]).to eq("2")

      delete "/MedicationAdministration/#{id}"
      expect(response).to have_http_status(:no_content)
    end
  end

  describe "GET /MedicationAdministration (search)" do
    it "finds by subject reference" do
      subject_id = create_patient
      post "/MedicationAdministration", params: valid_medication_administration_payload(subject_id: subject_id), as: :json

      get "/MedicationAdministration", params: { subject: "Patient/#{subject_id}" }

      bundle = JSON.parse(response.body)
      expect(bundle["type"]).to eq("searchset")
      expect(bundle["total"]).to eq(1)
    end

    it "finds by request reference" do
      subject_id = create_patient
      post "/MedicationRequest", params: valid_medication_request_payload(subject_id: subject_id), as: :json
      request_id = JSON.parse(response.body)["id"]
      post "/MedicationAdministration",
           params: valid_medication_administration_payload(
             subject_id: subject_id, request: { "reference" => "MedicationRequest/#{request_id}" }
           ),
           as: :json

      get "/MedicationAdministration", params: { request: "MedicationRequest/#{request_id}" }

      expect(JSON.parse(response.body)["total"]).to eq(1)
    end

    it "includes the referenced Patient via MedicationAdministration:subject" do
      subject_id = create_patient
      post "/MedicationAdministration", params: valid_medication_administration_payload(subject_id: subject_id), as: :json
      id = JSON.parse(response.body)["id"]

      get "/MedicationAdministration", params: { _id: id, _include: "MedicationAdministration:subject" }

      bundle = JSON.parse(response.body)
      included = bundle["entry"].select { |entry| entry.dig("search", "mode") == "include" }
      expect(included.map { |entry| entry["resource"]["resourceType"] }).to eq(["Patient"])
    end
  end
end
