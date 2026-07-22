require "rails_helper"

RSpec.describe "Procedures", type: :request do
  def create_patient
    post "/Patient", params: valid_patient_payload, as: :json
    JSON.parse(response.body)["id"]
  end

  describe "POST /Procedure" do
    it "creates and returns 201 with Location, ETag, and meta" do
      subject_id = create_patient

      post "/Procedure", params: valid_procedure_payload(subject_id: subject_id), as: :json

      expect(response).to have_http_status(:created)
      expect(response.content_type).to include("application/fhir+json")
      expect(response.headers["Location"]).to match(%r{/Procedure/[\w-]+/_history/1\z})
      expect(response.headers["ETag"]).to eq('W/"1"')

      body = JSON.parse(response.body)
      expect(body["resourceType"]).to eq("Procedure")
      expect(body["meta"]["profile"]).to eq(["http://jpfhir.jp/fhir/core/StructureDefinition/JP_Procedure"])
    end

    it "returns 422 when status is missing" do
      subject_id = create_patient

      post "/Procedure", params: valid_procedure_payload(subject_id: subject_id).except("status"), as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "returns 422 for an invalid status" do
      subject_id = create_patient

      post "/Procedure", params: valid_procedure_payload(subject_id: subject_id, status: "bogus"), as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "returns 422 when subject references a non-existent patient" do
      post "/Procedure", params: valid_procedure_payload(subject_id: "does-not-exist"), as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "GET /Procedure/:id" do
    it "returns the resource" do
      subject_id = create_patient
      post "/Procedure", params: valid_procedure_payload(subject_id: subject_id), as: :json
      id = JSON.parse(response.body)["id"]

      get "/Procedure/#{id}"

      expect(response).to have_http_status(:ok)
    end

    it "returns 404 for an unknown id" do
      get "/Procedure/does-not-exist"

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "PUT and DELETE" do
    it "updates and then deletes" do
      subject_id = create_patient
      post "/Procedure", params: valid_procedure_payload(subject_id: subject_id), as: :json
      id = JSON.parse(response.body)["id"]

      put "/Procedure/#{id}", params: valid_procedure_payload(subject_id: subject_id, status: "entered-in-error"), as: :json
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["meta"]["versionId"]).to eq("2")

      delete "/Procedure/#{id}"
      expect(response).to have_http_status(:no_content)

      get "/Procedure/#{id}"
      expect(response).to have_http_status(:gone)
    end
  end

  describe "GET /Procedure (search)" do
    it "finds by subject reference" do
      subject_id = create_patient
      post "/Procedure", params: valid_procedure_payload(subject_id: subject_id), as: :json

      get "/Procedure", params: { subject: "Patient/#{subject_id}" }

      bundle = JSON.parse(response.body)
      expect(bundle["type"]).to eq("searchset")
      expect(bundle["total"]).to eq(1)
    end

    it "finds by code" do
      subject_id = create_patient
      post "/Procedure", params: valid_procedure_payload(subject_id: subject_id), as: :json

      get "/Procedure", params: { code: "80146002" }

      expect(JSON.parse(response.body)["total"]).to be >= 1
    end

    it "includes the referenced Patient via Procedure:subject" do
      subject_id = create_patient
      post "/Procedure", params: valid_procedure_payload(subject_id: subject_id), as: :json
      id = JSON.parse(response.body)["id"]

      get "/Procedure", params: { _id: id, _include: "Procedure:subject" }

      bundle = JSON.parse(response.body)
      included = bundle["entry"].select { |entry| entry.dig("search", "mode") == "include" }
      expect(included.map { |entry| entry["resource"]["resourceType"] }).to eq(["Patient"])
    end
  end
end
