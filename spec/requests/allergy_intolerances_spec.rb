require "rails_helper"

RSpec.describe "AllergyIntolerances", type: :request do
  def create_patient
    post "/Patient", params: valid_patient_payload, as: :json
    JSON.parse(response.body)["id"]
  end

  describe "POST /AllergyIntolerance" do
    it "creates and returns 201 with Location, ETag, and meta" do
      patient_id = create_patient

      post "/AllergyIntolerance", params: valid_allergy_intolerance_payload(patient_id: patient_id), as: :json

      expect(response).to have_http_status(:created)
      expect(response.content_type).to include("application/fhir+json")
      expect(response.headers["Location"]).to match(%r{/AllergyIntolerance/[\w-]+/_history/1\z})
      expect(response.headers["ETag"]).to eq('W/"1"')

      body = JSON.parse(response.body)
      expect(body["resourceType"]).to eq("AllergyIntolerance")
      expect(body["meta"]["profile"]).to eq(["http://jpfhir.jp/fhir/core/StructureDefinition/JP_AllergyIntolerance"])
    end

    it "returns 422 for an invalid criticality" do
      patient_id = create_patient

      post "/AllergyIntolerance",
           params: valid_allergy_intolerance_payload(patient_id: patient_id, criticality: "bogus"), as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "returns 422 when patient references a non-existent patient" do
      post "/AllergyIntolerance", params: valid_allergy_intolerance_payload(patient_id: "does-not-exist"), as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "GET /AllergyIntolerance/:id" do
    it "returns the resource" do
      patient_id = create_patient
      post "/AllergyIntolerance", params: valid_allergy_intolerance_payload(patient_id: patient_id), as: :json
      id = JSON.parse(response.body)["id"]

      get "/AllergyIntolerance/#{id}"

      expect(response).to have_http_status(:ok)
    end

    it "returns 404 for an unknown id" do
      get "/AllergyIntolerance/does-not-exist"

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "PUT and DELETE" do
    it "updates and then deletes" do
      patient_id = create_patient
      post "/AllergyIntolerance", params: valid_allergy_intolerance_payload(patient_id: patient_id), as: :json
      id = JSON.parse(response.body)["id"]

      put "/AllergyIntolerance/#{id}",
          params: valid_allergy_intolerance_payload(patient_id: patient_id, criticality: "low"), as: :json
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["meta"]["versionId"]).to eq("2")

      delete "/AllergyIntolerance/#{id}"
      expect(response).to have_http_status(:no_content)

      get "/AllergyIntolerance/#{id}"
      expect(response).to have_http_status(:gone)
    end
  end

  describe "GET /AllergyIntolerance (search)" do
    it "finds by patient reference" do
      patient_id = create_patient
      post "/AllergyIntolerance", params: valid_allergy_intolerance_payload(patient_id: patient_id), as: :json

      get "/AllergyIntolerance", params: { patient: "Patient/#{patient_id}" }

      bundle = JSON.parse(response.body)
      expect(bundle["type"]).to eq("searchset")
      expect(bundle["total"]).to eq(1)
    end

    it "finds by category" do
      patient_id = create_patient
      post "/AllergyIntolerance", params: valid_allergy_intolerance_payload(patient_id: patient_id), as: :json

      get "/AllergyIntolerance", params: { category: "medication" }

      expect(JSON.parse(response.body)["total"]).to be >= 1
    end

    it "includes the referenced Patient via AllergyIntolerance:patient" do
      patient_id = create_patient
      post "/AllergyIntolerance", params: valid_allergy_intolerance_payload(patient_id: patient_id), as: :json
      id = JSON.parse(response.body)["id"]

      get "/AllergyIntolerance", params: { _id: id, _include: "AllergyIntolerance:patient" }

      bundle = JSON.parse(response.body)
      included = bundle["entry"].select { |entry| entry.dig("search", "mode") == "include" }
      expect(included.map { |entry| entry["resource"]["resourceType"] }).to eq(["Patient"])
    end
  end


  # 一覧が表示するのは発症日(onsetDateTime)なので、並べ替えも onset で行える
  # ようにした(以前は検索パラメータが無く、記録日 date で代用していた)。
  describe "onset search parameter" do
    def create_allergy(patient_id, onset: nil, recorded: nil)
      overrides = {}
      overrides["onsetDateTime"] = onset if onset
      overrides["recordedDate"] = recorded if recorded
      post "/AllergyIntolerance",
           params: valid_allergy_intolerance_payload(patient_id: patient_id, **overrides), as: :json
      expect(response).to have_http_status(:created), "setup failed: #{response.body}"
      JSON.parse(response.body)["id"]
    end

    it "filters by onset independently of recordedDate" do
      patient_id = create_patient
      old_onset = create_allergy(patient_id, onset: "2020-05-01", recorded: "2026-08-20T10:00:00+09:00")
      new_onset = create_allergy(patient_id, onset: "2024-03-15", recorded: "2026-08-01T10:00:00+09:00")

      get "/AllergyIntolerance?patient=Patient/#{patient_id}&onset=ge2023-01-01"

      bundle = JSON.parse(response.body)
      expect(bundle["entry"].map { |e| e["resource"]["id"] }).to eq([new_onset])
      # date(記録日)で引くと逆になる = 別の軸であることの確認。
      get "/AllergyIntolerance?patient=Patient/#{patient_id}&date=ge2026-08-10"
      expect(JSON.parse(response.body)["entry"].map { |e| e["resource"]["id"] }).to eq([old_onset])
    end

    it "sorts newest onset first, with undated entries last" do
      patient_id = create_patient
      older = create_allergy(patient_id, onset: "2020-05-01")
      undated = create_allergy(patient_id)
      newer = create_allergy(patient_id, onset: "2024-03-15")

      get "/AllergyIntolerance?patient=Patient/#{patient_id}&_sort=-onset"

      # 発症日未設定は末尾(Postgres の DESC 既定は NULLS FIRST なので明示している)。
      expect(JSON.parse(response.body)["entry"].map { |e| e["resource"]["id"] })
        .to eq([newer, older, undated])
    end

    it "supports onset:missing" do
      patient_id = create_patient
      create_allergy(patient_id, onset: "2020-05-01")
      undated = create_allergy(patient_id)

      get "/AllergyIntolerance?patient=Patient/#{patient_id}&onset:missing=true"
      expect(JSON.parse(response.body)["entry"].map { |e| e["resource"]["id"] }).to eq([undated])
    end
  end
end
