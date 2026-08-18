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
      expect(body["meta"]["profile"]).to eq(["http://jpfhir.jp/fhir/core/StructureDefinition/JP_Specimen_Common"])
    end

    it "returns 422 for an invalid status" do
      subject_id = create_patient

      post "/Specimen", params: valid_specimen_payload(subject_id: subject_id, status: "bogus"), as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "returns 422 when subject references a non-existent patient" do
      post "/Specimen", params: valid_specimen_payload(subject_id: "does-not-exist"), as: :json

      expect(response).to have_http_status(:unprocessable_content)
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

  # Specimen.request は採取の元になったオーダー。検体検査のワークリストが
  # 「このオーダーの管がどこまで揃ったか」を引くのに使う。
  describe "request (採取の元になったオーダー)" do
    def create_service_request(subject_id)
      post "/ServiceRequest", params: valid_service_request_payload(subject_id: subject_id), as: :json
      JSON.parse(response.body)["id"]
    end

    def create_specimen(subject_id, order_id: nil)
      overrides =
        order_id ? { "request" => [{ "reference" => "ServiceRequest/#{order_id}" }] } : {}
      post "/Specimen", params: valid_specimen_payload(subject_id: subject_id, **overrides), as: :json
      JSON.parse(response.body)["id"]
    end

    def entry_ids(mode)
      JSON.parse(response.body)["entry"].to_a
          .select { |entry| entry.dig("search", "mode") == mode }
          .map { |entry| entry.dig("resource", "id") }
    end

    it "finds only the specimens of the given order" do
      subject_id = create_patient
      order_id = create_service_request(subject_id)
      other_order_id = create_service_request(subject_id)
      specimen_id = create_specimen(subject_id, order_id: order_id)
      create_specimen(subject_id, order_id: other_order_id)
      create_specimen(subject_id)

      get "/Specimen", params: { request: "ServiceRequest/#{order_id}" }

      expect(JSON.parse(response.body)["total"]).to eq(1)
      expect(entry_ids("match")).to eq([specimen_id])
    end

    it "includes the specimens with _revinclude=Specimen:request" do
      subject_id = create_patient
      order_id = create_service_request(subject_id)
      specimen_id = create_specimen(subject_id, order_id: order_id)
      create_specimen(subject_id)

      get "/ServiceRequest", params: { _id: order_id, _revinclude: "Specimen:request" }

      expect(entry_ids("match")).to eq([order_id])
      expect(entry_ids("include")).to eq([specimen_id])
    end

    it "includes the order with _include=Specimen:request" do
      subject_id = create_patient
      order_id = create_service_request(subject_id)
      specimen_id = create_specimen(subject_id, order_id: order_id)

      get "/Specimen", params: { _id: specimen_id, _include: "Specimen:request" }

      expect(entry_ids("match")).to eq([specimen_id])
      expect(entry_ids("include")).to eq([order_id])
    end
  end
end
