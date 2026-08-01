require "rails_helper"

RSpec.describe "Groups", type: :request do
  def create_patient
    post "/Patient", params: valid_patient_payload, as: :json
    JSON.parse(response.body)["id"]
  end

  def create_organization
    post "/Organization", params: valid_organization_payload, as: :json
    JSON.parse(response.body)["id"]
  end

  def create_group(**args)
    post "/Group", params: valid_group_payload(**args), as: :json
    JSON.parse(response.body)["id"]
  end

  describe "POST /Group" do
    it "creates and returns 201 with Location, ETag, and meta" do
      post "/Group", params: valid_group_payload, as: :json

      expect(response).to have_http_status(:created)
      expect(response.content_type).to include("application/fhir+json")
      expect(response.headers["Location"]).to match(%r{/Group/[\w-]+/_history/1\z})
      expect(response.headers["ETag"]).to eq('W/"1"')

      body = JSON.parse(response.body)
      expect(body["resourceType"]).to eq("Group")
      # Group is the one registered type JP Core does not profile.
      expect(body["meta"]["profile"]).to eq(["http://hl7.org/fhir/StructureDefinition/Group"])
    end

    it "returns 422 for an invalid type" do
      post "/Group", params: valid_group_payload(type: "bogus"), as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "returns 422 without actual" do
      post "/Group", params: valid_group_payload.except("actual"), as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "returns 422 when a member references a non-existent patient" do
      post "/Group", params: valid_group_payload(member_ids: ["does-not-exist"]), as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "returns 422 for members on a descriptive group (grp-1)" do
      patient_id = create_patient

      post "/Group", params: valid_group_payload(member_ids: [patient_id], actual: false), as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "GET /Group/:id" do
    it "returns the resource" do
      id = create_group

      get "/Group/#{id}"

      expect(response).to have_http_status(:ok)
    end

    it "returns 404 for an unknown id" do
      get "/Group/does-not-exist"

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "PUT and DELETE" do
    it "updates and then deletes" do
      id = create_group

      put "/Group/#{id}", params: valid_group_payload(name: "改訂版コホート"), as: :json
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["meta"]["versionId"]).to eq("2")

      delete "/Group/#{id}"
      expect(response).to have_http_status(:no_content)

      get "/Group/#{id}"
      expect(response).to have_http_status(:gone)
    end
  end

  describe "GET /Group (search)" do
    it "finds by identifier" do
      create_group

      get "/Group", params: { identifier: "GRP1" }

      bundle = JSON.parse(response.body)
      expect(bundle["type"]).to eq("searchset")
      expect(bundle["total"]).to eq(1)
    end

    it "finds by type, code, and actual" do
      create_group

      get "/Group", params: { type: "person", code: "checkup-2026", actual: "true" }

      expect(JSON.parse(response.body)["total"]).to eq(1)
    end

    it "finds by managing-entity" do
      organization_id = create_organization
      create_group(managing_entity_id: organization_id)

      get "/Group", params: { "managing-entity" => "Organization/#{organization_id}" }

      expect(JSON.parse(response.body)["total"]).to eq(1)
    end

    # member is 0..*, so it is matched by jsonb containment rather than a column.
    it "finds by member" do
      patient_id = create_patient
      other_patient_id = create_patient
      create_group(member_ids: [other_patient_id, patient_id])

      get "/Group", params: { member: "Patient/#{patient_id}" }

      expect(JSON.parse(response.body)["total"]).to eq(1)
    end

    it "includes member Patients via Group:member" do
      patient_id = create_patient
      id = create_group(member_ids: [patient_id])

      get "/Group", params: { _id: id, _include: "Group:member" }

      bundle = JSON.parse(response.body)
      included = bundle["entry"].select { |entry| entry.dig("search", "mode") == "include" }
      expect(included.map { |entry| entry["resource"]["resourceType"] }).to eq(["Patient"])
    end
  end

  describe "capability statement" do
    it "advertises Group with the base HL7 profile" do
      get "/metadata"

      resource = JSON.parse(response.body)["rest"].first["resource"].find { |r| r["type"] == "Group" }
      expect(resource["profile"]).to eq("http://hl7.org/fhir/StructureDefinition/Group")
      expect(resource["searchParam"].map { |p| p["name"] }).to include("member", "managing-entity", "actual")
    end
  end
end
