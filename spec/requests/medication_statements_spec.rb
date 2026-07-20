require "rails_helper"

RSpec.describe "MedicationStatements", type: :request do
  def create_patient
    post "/Patient", params: valid_patient_payload, as: :json
    JSON.parse(response.body)["id"]
  end

  describe "POST /MedicationStatement" do
    it "creates and returns 201 with Location, ETag, and meta" do
      subject_id = create_patient

      post "/MedicationStatement", params: valid_medication_statement_payload(subject_id: subject_id), as: :json

      expect(response).to have_http_status(:created)
      expect(response.headers["Location"]).to match(%r{/MedicationStatement/[\w-]+/_history/1\z})
      expect(response.headers["ETag"]).to eq('W/"1"')

      body = JSON.parse(response.body)
      expect(body["resourceType"]).to eq("MedicationStatement")
      expect(body["meta"]["profile"]).to eq(["http://jpfhir.jp/fhir/core/StructureDefinition/JP_MedicationStatement"])
    end

    it "returns 422 when status is missing" do
      subject_id = create_patient

      post "/MedicationStatement",
           params: valid_medication_statement_payload(subject_id: subject_id).except("status"), as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "returns 422 when medication[x] is missing" do
      subject_id = create_patient

      post "/MedicationStatement",
           params: valid_medication_statement_payload(subject_id: subject_id).except("medicationCodeableConcept"), as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "returns 422 when subject references a non-existent patient" do
      post "/MedicationStatement", params: valid_medication_statement_payload(subject_id: "does-not-exist"), as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "GET /MedicationStatement/:id" do
    it "returns the resource" do
      subject_id = create_patient
      post "/MedicationStatement", params: valid_medication_statement_payload(subject_id: subject_id), as: :json
      id = JSON.parse(response.body)["id"]

      get "/MedicationStatement/#{id}"

      expect(response).to have_http_status(:ok)
    end

    it "returns 404 for an unknown id" do
      get "/MedicationStatement/does-not-exist"

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "PUT and DELETE" do
    it "updates and then deletes" do
      subject_id = create_patient
      post "/MedicationStatement", params: valid_medication_statement_payload(subject_id: subject_id), as: :json
      id = JSON.parse(response.body)["id"]

      put "/MedicationStatement/#{id}",
          params: valid_medication_statement_payload(subject_id: subject_id, status: "completed"), as: :json
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["meta"]["versionId"]).to eq("2")

      delete "/MedicationStatement/#{id}"
      expect(response).to have_http_status(:no_content)
    end
  end

  describe "GET /MedicationStatement (search)" do
    it "finds by subject reference" do
      subject_id = create_patient
      post "/MedicationStatement", params: valid_medication_statement_payload(subject_id: subject_id), as: :json

      get "/MedicationStatement", params: { subject: "Patient/#{subject_id}" }

      bundle = JSON.parse(response.body)
      expect(bundle["type"]).to eq("searchset")
      expect(bundle["total"]).to eq(1)
    end

    it "finds by status" do
      subject_id = create_patient
      post "/MedicationStatement",
           params: valid_medication_statement_payload(subject_id: subject_id, status: "completed"), as: :json

      get "/MedicationStatement", params: { status: "completed" }

      expect(JSON.parse(response.body)["total"]).to be >= 1
    end

    it "includes the referenced Patient via MedicationStatement:subject" do
      subject_id = create_patient
      post "/MedicationStatement", params: valid_medication_statement_payload(subject_id: subject_id), as: :json
      id = JSON.parse(response.body)["id"]

      get "/MedicationStatement", params: { _id: id, _include: "MedicationStatement:subject" }

      bundle = JSON.parse(response.body)
      included = bundle["entry"].select { |entry| entry.dig("search", "mode") == "include" }
      expect(included.map { |entry| entry["resource"]["resourceType"] }).to eq(["Patient"])
    end
  end
end
