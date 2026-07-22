require "rails_helper"

RSpec.describe "ImagingStudies", type: :request do
  def create_patient
    post "/Patient", params: valid_patient_payload, as: :json
    JSON.parse(response.body)["id"]
  end

  describe "POST /ImagingStudy" do
    it "creates and returns 201 with Location, ETag, and meta" do
      subject_id = create_patient

      post "/ImagingStudy", params: valid_imaging_study_payload(subject_id: subject_id), as: :json

      expect(response).to have_http_status(:created)
      expect(response.headers["Location"]).to match(%r{/ImagingStudy/[\w-]+/_history/1\z})
      expect(response.headers["ETag"]).to eq('W/"1"')

      body = JSON.parse(response.body)
      expect(body["resourceType"]).to eq("ImagingStudy")
      expect(body["meta"]["profile"]).to eq(["http://hl7.org/fhir/StructureDefinition/ImagingStudy"])
    end

    it "returns 422 when status is missing" do
      subject_id = create_patient

      post "/ImagingStudy", params: valid_imaging_study_payload(subject_id: subject_id).except("status"), as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "returns 422 for an invalid status" do
      subject_id = create_patient

      post "/ImagingStudy", params: valid_imaging_study_payload(subject_id: subject_id, status: "bogus"), as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "returns 422 when subject references a non-existent patient" do
      post "/ImagingStudy", params: valid_imaging_study_payload(subject_id: "does-not-exist"), as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "GET /ImagingStudy/:id" do
    it "returns the resource" do
      subject_id = create_patient
      post "/ImagingStudy", params: valid_imaging_study_payload(subject_id: subject_id), as: :json
      id = JSON.parse(response.body)["id"]

      get "/ImagingStudy/#{id}"

      expect(response).to have_http_status(:ok)
    end

    it "returns 404 for an unknown id" do
      get "/ImagingStudy/does-not-exist"

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "PUT and DELETE" do
    it "updates and then deletes" do
      subject_id = create_patient
      post "/ImagingStudy", params: valid_imaging_study_payload(subject_id: subject_id), as: :json
      id = JSON.parse(response.body)["id"]

      put "/ImagingStudy/#{id}", params: valid_imaging_study_payload(subject_id: subject_id, status: "registered"), as: :json
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["meta"]["versionId"]).to eq("2")

      delete "/ImagingStudy/#{id}"
      expect(response).to have_http_status(:no_content)
    end
  end

  describe "GET /ImagingStudy (search)" do
    it "finds by subject reference" do
      subject_id = create_patient
      post "/ImagingStudy", params: valid_imaging_study_payload(subject_id: subject_id), as: :json

      get "/ImagingStudy", params: { subject: "Patient/#{subject_id}" }

      bundle = JSON.parse(response.body)
      expect(bundle["type"]).to eq("searchset")
      expect(bundle["total"]).to eq(1)
    end

    it "finds by modality" do
      subject_id = create_patient
      post "/ImagingStudy", params: valid_imaging_study_payload(subject_id: subject_id), as: :json

      get "/ImagingStudy", params: { modality: "CT" }

      expect(JSON.parse(response.body)["total"]).to be >= 1
    end

    it "includes the referenced Patient via ImagingStudy:subject" do
      subject_id = create_patient
      post "/ImagingStudy", params: valid_imaging_study_payload(subject_id: subject_id), as: :json
      id = JSON.parse(response.body)["id"]

      get "/ImagingStudy", params: { _id: id, _include: "ImagingStudy:subject" }

      bundle = JSON.parse(response.body)
      included = bundle["entry"].select { |entry| entry.dig("search", "mode") == "include" }
      expect(included.map { |entry| entry["resource"]["resourceType"] }).to eq(["Patient"])
    end
  end
end
