require "rails_helper"

RSpec.describe "DocumentReference", type: :request do
  def create_patient
    post "/Patient", params: valid_patient_payload, as: :json
    JSON.parse(response.body)["id"]
  end

  describe "create" do
    it "creates a valid document reference with 201" do
      patient_id = create_patient

      post "/DocumentReference", params: valid_document_reference_payload(subject_id: patient_id), as: :json

      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      expect(body["meta"]["versionId"]).to eq("1")
      expect(body["meta"]["profile"]).to eq(["http://hl7.org/fhir/StructureDefinition/DocumentReference"])
    end

    it "returns 422 when status is missing or invalid" do
      patient_id = create_patient

      post "/DocumentReference",
           params: valid_document_reference_payload(subject_id: patient_id).except("status"), as: :json
      expect(response).to have_http_status(:unprocessable_content)

      post "/DocumentReference",
           params: valid_document_reference_payload(subject_id: patient_id, status: "draft"), as: :json
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "returns 422 when content is missing or lacks an attachment" do
      patient_id = create_patient

      post "/DocumentReference",
           params: valid_document_reference_payload(subject_id: patient_id).except("content"), as: :json
      expect(response).to have_http_status(:unprocessable_content)

      post "/DocumentReference",
           params: valid_document_reference_payload(subject_id: patient_id, content: [{}]), as: :json
      expect(response).to have_http_status(:unprocessable_content)
      expect(JSON.parse(response.body)["issue"].first["expression"]).to include("DocumentReference.content[0].attachment")
    end

    it "returns 422 for an invalid docStatus" do
      patient_id = create_patient

      post "/DocumentReference",
           params: valid_document_reference_payload(subject_id: patient_id, docStatus: "draft"), as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "search" do
    it "finds documents by patient, status, type text, and date" do
      patient_id = create_patient
      other_id = create_patient
      post "/DocumentReference", params: valid_document_reference_payload(subject_id: patient_id), as: :json
      post "/DocumentReference",
           params: valid_document_reference_payload(subject_id: other_id, status: "superseded"), as: :json

      get "/DocumentReference?patient=#{patient_id}"
      expect(JSON.parse(response.body)["total"]).to eq(1)

      get "/DocumentReference?status=current"
      expect(JSON.parse(response.body)["total"]).to eq(1)

      get "/DocumentReference?type=#{Rack::Utils.escape('退院時サマリ')}"
      expect(JSON.parse(response.body)["total"]).to eq(2)

      get "/DocumentReference?date=ge2026-07-01&date=le2026-08-01"
      expect(JSON.parse(response.body)["total"]).to eq(2)
    end
  end

  it "joins the patient compartment ($everything)" do
    patient_id = create_patient
    post "/DocumentReference", params: valid_document_reference_payload(subject_id: patient_id), as: :json

    get "/Patient/#{patient_id}/$everything"

    types = JSON.parse(response.body)["entry"].map { |e| e.dig("resource", "resourceType") }
    expect(types).to contain_exactly("Patient", "DocumentReference")
  end
end
