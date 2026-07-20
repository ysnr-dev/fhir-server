require "rails_helper"

RSpec.describe "Coverages", type: :request do
  def create_patient
    post "/Patient", params: valid_patient_payload, as: :json
    JSON.parse(response.body)["id"]
  end

  def create_organization
    post "/Organization", params: valid_organization_payload, as: :json
    JSON.parse(response.body)["id"]
  end

  describe "POST /Coverage" do
    it "creates and returns 201 with Location, ETag, and meta" do
      beneficiary_id = create_patient
      payor_id = create_organization

      post "/Coverage", params: valid_coverage_payload(beneficiary_id: beneficiary_id, payor_id: payor_id), as: :json

      expect(response).to have_http_status(:created)
      expect(response.content_type).to include("application/fhir+json")
      expect(response.headers["Location"]).to match(%r{/Coverage/[\w-]+/_history/1\z})
      expect(response.headers["ETag"]).to eq('W/"1"')

      body = JSON.parse(response.body)
      expect(body["resourceType"]).to eq("Coverage")
      expect(body["meta"]["profile"]).to eq(["http://jpfhir.jp/fhir/core/StructureDefinition/JP_Coverage"])
    end

    it "returns 422 when payor is missing" do
      beneficiary_id = create_patient
      payor_id = create_organization

      post "/Coverage",
           params: valid_coverage_payload(beneficiary_id: beneficiary_id, payor_id: payor_id).except("payor"), as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "returns 422 for an invalid status" do
      beneficiary_id = create_patient
      payor_id = create_organization

      post "/Coverage",
           params: valid_coverage_payload(beneficiary_id: beneficiary_id, payor_id: payor_id, status: "bogus"), as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "returns 422 when beneficiary references a non-existent patient" do
      payor_id = create_organization

      post "/Coverage",
           params: valid_coverage_payload(beneficiary_id: "does-not-exist", payor_id: payor_id), as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "GET /Coverage/:id" do
    it "returns the resource" do
      beneficiary_id = create_patient
      payor_id = create_organization
      post "/Coverage", params: valid_coverage_payload(beneficiary_id: beneficiary_id, payor_id: payor_id), as: :json
      id = JSON.parse(response.body)["id"]

      get "/Coverage/#{id}"

      expect(response).to have_http_status(:ok)
    end

    it "returns 404 for an unknown id" do
      get "/Coverage/does-not-exist"

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "PUT and DELETE" do
    it "updates and then deletes" do
      beneficiary_id = create_patient
      payor_id = create_organization
      post "/Coverage", params: valid_coverage_payload(beneficiary_id: beneficiary_id, payor_id: payor_id), as: :json
      id = JSON.parse(response.body)["id"]

      put "/Coverage/#{id}",
          params: valid_coverage_payload(beneficiary_id: beneficiary_id, payor_id: payor_id, status: "cancelled"),
          as: :json
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["meta"]["versionId"]).to eq("2")

      delete "/Coverage/#{id}"
      expect(response).to have_http_status(:no_content)

      get "/Coverage/#{id}"
      expect(response).to have_http_status(:gone)
    end
  end

  describe "GET /Coverage (search)" do
    it "finds by beneficiary reference" do
      beneficiary_id = create_patient
      payor_id = create_organization
      post "/Coverage", params: valid_coverage_payload(beneficiary_id: beneficiary_id, payor_id: payor_id), as: :json

      get "/Coverage", params: { beneficiary: "Patient/#{beneficiary_id}" }

      bundle = JSON.parse(response.body)
      expect(bundle["type"]).to eq("searchset")
      expect(bundle["total"]).to eq(1)
    end

    it "finds by payor reference (jsonb containment)" do
      beneficiary_id = create_patient
      payor_id = create_organization
      post "/Coverage", params: valid_coverage_payload(beneficiary_id: beneficiary_id, payor_id: payor_id), as: :json

      get "/Coverage", params: { payor: "Organization/#{payor_id}" }

      expect(JSON.parse(response.body)["total"]).to eq(1)
    end

    it "includes the referenced Patient via Coverage:beneficiary" do
      beneficiary_id = create_patient
      payor_id = create_organization
      post "/Coverage", params: valid_coverage_payload(beneficiary_id: beneficiary_id, payor_id: payor_id), as: :json
      id = JSON.parse(response.body)["id"]

      get "/Coverage", params: { _id: id, _include: "Coverage:beneficiary" }

      bundle = JSON.parse(response.body)
      included = bundle["entry"].select { |entry| entry.dig("search", "mode") == "include" }
      expect(included.map { |entry| entry["resource"]["resourceType"] }).to eq(["Patient"])
    end
  end
end
