require "rails_helper"

RSpec.describe "Devices", type: :request do
  def create_patient
    post "/Patient", params: valid_patient_payload, as: :json
    JSON.parse(response.body)["id"]
  end

  def create_organization
    post "/Organization", params: valid_organization_payload, as: :json
    JSON.parse(response.body)["id"]
  end

  def create_device(**args)
    post "/Device", params: valid_device_payload(**args), as: :json
    JSON.parse(response.body)["id"]
  end

  describe "POST /Device" do
    it "creates and returns 201 with Location, ETag, and meta" do
      post "/Device", params: valid_device_payload, as: :json

      expect(response).to have_http_status(:created)
      expect(response.content_type).to include("application/fhir+json")
      expect(response.headers["Location"]).to match(%r{/Device/[\w-]+/_history/1\z})
      expect(response.headers["ETag"]).to eq('W/"1"')

      body = JSON.parse(response.body)
      expect(body["resourceType"]).to eq("Device")
      expect(body["meta"]["profile"]).to eq(["http://jpfhir.jp/fhir/core/StructureDefinition/JP_Device"])
    end

    it "returns 422 for an invalid status" do
      post "/Device", params: valid_device_payload(status: "bogus"), as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "returns 422 when patient references a non-existent patient" do
      post "/Device", params: valid_device_payload(patient_id: "does-not-exist"), as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "GET /Device/:id" do
    it "returns the resource" do
      id = create_device

      get "/Device/#{id}"

      expect(response).to have_http_status(:ok)
    end

    it "returns 404 for an unknown id" do
      get "/Device/does-not-exist"

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "PUT and DELETE" do
    it "updates and then deletes" do
      id = create_device

      put "/Device/#{id}", params: valid_device_payload(status: "inactive"), as: :json
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["meta"]["versionId"]).to eq("2")

      delete "/Device/#{id}"
      expect(response).to have_http_status(:no_content)

      get "/Device/#{id}"
      expect(response).to have_http_status(:gone)
    end
  end

  describe "GET /Device (search)" do
    it "finds by identifier" do
      create_device

      get "/Device", params: { identifier: "DEV1" }

      bundle = JSON.parse(response.body)
      expect(bundle["type"]).to eq("searchset")
      expect(bundle["total"]).to eq(1)
    end

    it "finds by status and type" do
      create_device

      get "/Device", params: { status: "active", type: "706172005" }

      expect(JSON.parse(response.body)["total"]).to eq(1)
    end

    it "finds by patient reference" do
      patient_id = create_patient
      create_device(patient_id: patient_id)

      get "/Device", params: { patient: "Patient/#{patient_id}" }

      expect(JSON.parse(response.body)["total"]).to eq(1)
    end

    it "finds by organization (Device.owner)" do
      organization_id = create_organization
      create_device(owner_id: organization_id)

      get "/Device", params: { organization: "Organization/#{organization_id}" }

      expect(JSON.parse(response.body)["total"]).to eq(1)
    end

    # device_name_text joins every deviceName entry, so the search has to match
    # on a word boundary rather than a plain prefix.
    it "finds by device-name matching a non-first name entry" do
      create_device(deviceName: [
                      { "name" => "サンプル人工呼吸器", "type" => "user-friendly-name" },
                      { "name" => "SampleVent", "type" => "manufacturer-name" }
                    ])

      get "/Device", params: { "device-name" => "SampleVent" }

      expect(JSON.parse(response.body)["total"]).to eq(1)
    end

    it "finds by manufacturer and model" do
      create_device

      get "/Device", params: { manufacturer: "サンプル", model: "SM-100" }

      expect(JSON.parse(response.body)["total"]).to eq(1)
    end

    it "finds by url" do
      create_device

      get "/Device", params: { url: "http://example.org/devices/DEV1" }

      expect(JSON.parse(response.body)["total"]).to eq(1)
    end

    it "includes the referenced Patient via Device:patient" do
      patient_id = create_patient
      id = create_device(patient_id: patient_id)

      get "/Device", params: { _id: id, _include: "Device:patient" }

      bundle = JSON.parse(response.body)
      included = bundle["entry"].select { |entry| entry.dig("search", "mode") == "include" }
      expect(included.map { |entry| entry["resource"]["resourceType"] }).to eq(["Patient"])
    end
  end

  describe "capability statement" do
    it "advertises Device with its JP Core profile" do
      get "/metadata"

      resource = JSON.parse(response.body)["rest"].first["resource"].find { |r| r["type"] == "Device" }
      expect(resource["profile"]).to eq("http://jpfhir.jp/fhir/core/StructureDefinition/JP_Device")
      expect(resource["searchParam"].map { |p| p["name"] }).to include("device-name", "organization", "patient")
    end
  end
end
