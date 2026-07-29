require "rails_helper"

RSpec.describe "Questionnaire", type: :request do
  describe "create" do
    it "creates a valid questionnaire with 201" do
      post "/Questionnaire", params: valid_questionnaire_payload, as: :json

      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      expect(body["meta"]["versionId"]).to eq("1")
      expect(body["meta"]["profile"])
        .to eq(["http://www.hosp.ncgm.go.jp/JASPEHR/fhir/StructureDefinition/jaspehr-questionnaire"])
      expect(response.headers["ETag"]).to eq('W/"1"')
      expect(response.headers["Location"]).to end_with("/Questionnaire/#{body['id']}/_history/1")
    end

    it "returns 422 when a JASPEHR-mandatory element is missing" do
      %w[version name title status subjectType item].each do |field|
        post "/Questionnaire", params: valid_questionnaire_payload.except(field), as: :json
        expect(response).to have_http_status(:unprocessable_content), "expected #{field} to be required"
      end
    end

    it "returns 422 for an item type JASPEHR excludes" do
      payload = valid_questionnaire_payload(
        "item" => [{ "linkId" => "q1", "type" => "boolean", "text" => "喫煙しますか" }]
      )

      post "/Questionnaire", params: payload, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("item.type")
    end

    it "returns 422 for a name longer than JASPEHR allows (jsp-5)" do
      post "/Questionnaire", params: valid_questionnaire_payload("name" => "A" * 16), as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("jsp-5")
    end
  end

  describe "read / update / delete lifecycle" do
    it "supports the full instance lifecycle" do
      post "/Questionnaire", params: valid_questionnaire_payload, as: :json
      id = JSON.parse(response.body)["id"]

      get "/Questionnaire/#{id}"
      expect(response).to have_http_status(:ok)

      put "/Questionnaire/#{id}", params: valid_questionnaire_payload("status" => "retired"), as: :json
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["meta"]["versionId"]).to eq("2")

      get "/Questionnaire/#{id}/_history/1"
      expect(JSON.parse(response.body)["status"]).to eq("active")

      delete "/Questionnaire/#{id}"
      expect(response).to have_http_status(:no_content)

      get "/Questionnaire/#{id}"
      expect(response).to have_http_status(:gone)
    end

    it "returns 404 for an unknown id" do
      get "/Questionnaire/does-not-exist"
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "search" do
    before do
      post "/Questionnaire", params: valid_questionnaire_payload, as: :json
      post "/Questionnaire", params: valid_questionnaire_payload(
        "url" => "http://example.org/Questionnaire/other",
        "name" => "OtherQ", "version" => "2.0.0", "title" => "別の問診票", "status" => "draft"
      ), as: :json
    end

    def total
      JSON.parse(response.body)["total"]
    end

    it "matches url exactly, never by prefix" do
      get "/Questionnaire?url=http://example.org/Questionnaire/jaspehr-example"
      expect(total).to eq(1)

      get "/Questionnaire?url=http://example.org/Questionnaire"
      expect(total).to eq(0)
    end

    it "finds questionnaires by status, version, name, title, code, subject-type, and date" do
      get "/Questionnaire?status=active"
      expect(total).to eq(1)

      get "/Questionnaire?version=2.0.0"
      expect(total).to eq(1)

      get "/Questionnaire?name=Example"
      expect(total).to eq(1)

      get "/Questionnaire", params: { title: "問診票" }
      expect(total).to eq(1)

      get "/Questionnaire?code=http://loinc.org|72166-2"
      expect(total).to eq(2)

      get "/Questionnaire?subject-type=Patient"
      expect(total).to eq(2)

      get "/Questionnaire?date=ge2026-07-01&date=le2026-08-01"
      expect(total).to eq(2)
    end
  end

  it "advertises url as a uri search parameter in the CapabilityStatement" do
    get "/metadata"

    component = JSON.parse(response.body).dig("rest", 0, "resource").find { |r| r["type"] == "Questionnaire" }
    expect(component["searchParam"]).to include({ "name" => "url", "type" => "uri" })
  end
end
