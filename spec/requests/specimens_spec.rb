require "rails_helper"

RSpec.describe "Specimens", type: :request do
  def create_patient
    post "/Patient", params: valid_patient_payload, as: :json
    JSON.parse(response.body)["id"]
  end

  describe "POST /Specimen" do
    it "creates and returns 201 with Location, ETag, and meta" do
      subject_id = create_patient

      post "/Specimen", params: valid_specimen_payload(subject_id: subject_id), as: :json

      expect(response).to have_http_status(:created)
      expect(response.content_type).to include("application/fhir+json")
      expect(response.headers["Location"]).to match(%r{/Specimen/[\w-]+/_history/1\z})
      expect(response.headers["ETag"]).to eq('W/"1"')

      body = JSON.parse(response.body)
      expect(body["resourceType"]).to eq("Specimen")
      expect(body["meta"]["profile"]).to eq(["http://jpfhir.jp/fhir/core/StructureDefinition/JP_Specimen"])
    end

    it "returns 422 for an invalid status" do
      subject_id = create_patient

      post "/Specimen", params: valid_specimen_payload(subject_id: subject_id, status: "bogus"), as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "returns 422 when subject references a non-existent patient" do
      post "/Specimen", params: valid_specimen_payload(subject_id: "does-not-exist"), as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "GET /Specimen/:id" do
    it "returns the resource" do
      subject_id = create_patient
      post "/Specimen", params: valid_specimen_payload(subject_id: subject_id), as: :json
      id = JSON.parse(response.body)["id"]

      get "/Specimen/#{id}"

      expect(response).to have_http_status(:ok)
    end

    it "returns 404 for an unknown id" do
      get "/Specimen/does-not-exist"

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "PUT and DELETE" do
    it "updates and then deletes" do
      subject_id = create_patient
      post "/Specimen", params: valid_specimen_payload(subject_id: subject_id), as: :json
      id = JSON.parse(response.body)["id"]

      put "/Specimen/#{id}", params: valid_specimen_payload(subject_id: subject_id, status: "unavailable"), as: :json
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["meta"]["versionId"]).to eq("2")

      delete "/Specimen/#{id}"
      expect(response).to have_http_status(:no_content)

      get "/Specimen/#{id}"
      expect(response).to have_http_status(:gone)
    end
  end

  describe "GET /Specimen (search)" do
    it "finds by subject reference" do
      subject_id = create_patient
      post "/Specimen", params: valid_specimen_payload(subject_id: subject_id), as: :json

      get "/Specimen", params: { subject: "Patient/#{subject_id}" }

      bundle = JSON.parse(response.body)
      expect(bundle["type"]).to eq("searchset")
      expect(bundle["total"]).to eq(1)
    end

    it "finds by type" do
      subject_id = create_patient
      post "/Specimen", params: valid_specimen_payload(subject_id: subject_id), as: :json

      get "/Specimen", params: { type: "BLD" }

      expect(JSON.parse(response.body)["total"]).to be >= 1
    end

    it "finds by accession identifier" do
      subject_id = create_patient
      post "/Specimen",
           params: valid_specimen_payload(
             subject_id: subject_id,
             accessionIdentifier: { "system" => "http://example.org", "value" => "ACC-42" }
           ),
           as: :json

      get "/Specimen", params: { accession: "ACC-42" }

      expect(JSON.parse(response.body)["total"]).to eq(1)
    end

    it "includes the referenced Patient via Specimen:subject" do
      subject_id = create_patient
      post "/Specimen", params: valid_specimen_payload(subject_id: subject_id), as: :json
      id = JSON.parse(response.body)["id"]

      get "/Specimen", params: { _id: id, _include: "Specimen:subject" }

      bundle = JSON.parse(response.body)
      included = bundle["entry"].select { |entry| entry.dig("search", "mode") == "include" }
      expect(included.map { |entry| entry["resource"]["resourceType"] }).to eq(["Patient"])
    end
  end
end
