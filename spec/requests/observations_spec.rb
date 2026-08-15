require "rails_helper"

RSpec.describe "Observations", type: :request do
  def create_patient
    post "/Patient", params: valid_patient_payload, as: :json
    JSON.parse(response.body)["id"]
  end

  describe "POST /Observation" do
    it "creates and returns 201 with Location, ETag, and meta" do
      subject_id = create_patient

      post "/Observation", params: valid_observation_payload(subject_id: subject_id), as: :json

      expect(response).to have_http_status(:created)
      expect(response.content_type).to include("application/fhir+json")
      expect(response.headers["Location"]).to match(%r{/Observation/[\w-]+/_history/1\z})
      expect(response.headers["ETag"]).to eq('W/"1"')

      body = JSON.parse(response.body)
      expect(body["resourceType"]).to eq("Observation")
      expect(body["meta"]["profile"]).to eq(["http://jpfhir.jp/fhir/core/StructureDefinition/JP_Observation_Common"])
    end

    it "returns 422 when status is missing" do
      subject_id = create_patient

      post "/Observation", params: valid_observation_payload(subject_id: subject_id).except("status"), as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "returns 422 for an invalid status" do
      subject_id = create_patient

      post "/Observation", params: valid_observation_payload(subject_id: subject_id, status: "bogus"), as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "returns 422 when code is missing" do
      subject_id = create_patient

      post "/Observation", params: valid_observation_payload(subject_id: subject_id).except("code"), as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "returns 422 when subject references a non-existent patient" do
      post "/Observation", params: valid_observation_payload(subject_id: "does-not-exist"), as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "returns 400 when resourceType does not match" do
      subject_id = create_patient

      post "/Observation", params: valid_observation_payload(subject_id: subject_id).merge("resourceType" => "Patient"), as: :json

      expect(response).to have_http_status(:bad_request)
    end
  end

  describe "GET /Observation/:id" do
    it "returns the resource" do
      subject_id = create_patient
      post "/Observation", params: valid_observation_payload(subject_id: subject_id), as: :json
      id = JSON.parse(response.body)["id"]

      get "/Observation/#{id}"

      expect(response).to have_http_status(:ok)
      expect(response.headers["ETag"]).to eq('W/"1"')
    end

    it "returns 404 for an unknown id" do
      get "/Observation/does-not-exist"

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "PUT and DELETE" do
    it "updates and then deletes" do
      subject_id = create_patient
      post "/Observation", params: valid_observation_payload(subject_id: subject_id), as: :json
      id = JSON.parse(response.body)["id"]

      put "/Observation/#{id}", params: valid_observation_payload(subject_id: subject_id, status: "amended"), as: :json
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["status"]).to eq("amended")
      expect(body["meta"]["versionId"]).to eq("2")

      delete "/Observation/#{id}"
      expect(response).to have_http_status(:no_content)

      get "/Observation/#{id}"
      expect(response).to have_http_status(:gone)
    end
  end

  describe "GET /Observation (search)" do
    it "finds by subject reference" do
      subject_id = create_patient
      post "/Observation", params: valid_observation_payload(subject_id: subject_id), as: :json

      get "/Observation", params: { subject: "Patient/#{subject_id}" }

      bundle = JSON.parse(response.body)
      expect(bundle["type"]).to eq("searchset")
      expect(bundle["total"]).to eq(1)
    end

    it "finds by code" do
      subject_id = create_patient
      post "/Observation", params: valid_observation_payload(subject_id: subject_id), as: :json

      get "/Observation", params: { code: "718-7" }

      expect(JSON.parse(response.body)["total"]).to be >= 1
    end

    it "finds by category" do
      subject_id = create_patient
      post "/Observation", params: valid_observation_payload(subject_id: subject_id), as: :json

      get "/Observation", params: { category: "laboratory" }

      expect(JSON.parse(response.body)["total"]).to be >= 1
    end

    # 実施記録に伴って測った値(放射線検査の被曝線量)。
    it "finds by part-of (the procedure it was measured during)" do
      subject_id = create_patient
      post "/Procedure", params: valid_procedure_payload(subject_id: subject_id), as: :json
      procedure_id = JSON.parse(response.body)["id"]
      post "/Observation",
           params: valid_observation_payload(
             subject_id: subject_id, partOf: [{ "reference" => "Procedure/#{procedure_id}" }]
           ),
           as: :json
      # 同じ患者の、実施に紐づかない検査値。part-of で拾われないことを確かめる。
      post "/Observation", params: valid_observation_payload(subject_id: subject_id), as: :json

      get "/Observation", params: { "part-of" => "Procedure/#{procedure_id}" }

      expect(JSON.parse(response.body)["total"]).to eq(1)
    end

    # テンプレート回答から抽出した値。回答を編集・削除する側が「前回この回答から
    # 作った Observation」を引き直すのに使う。
    it "finds by derived-from (the answer it was extracted from)" do
      subject_id = create_patient
      post "/Observation",
           params: valid_observation_payload(
             subject_id: subject_id, derivedFrom: [{ "reference" => "QuestionnaireResponse/qr1" }]
           ),
           as: :json
      derived_id = JSON.parse(response.body)["id"]
      # 別の回答から作った値と、抽出でない値。どちらも拾われないことを確かめる。
      post "/Observation",
           params: valid_observation_payload(
             subject_id: subject_id, derivedFrom: [{ "reference" => "QuestionnaireResponse/qr2" }]
           ),
           as: :json
      post "/Observation", params: valid_observation_payload(subject_id: subject_id), as: :json

      get "/Observation", params: { "derived-from" => "QuestionnaireResponse/qr1" }

      expect(JSON.parse(response.body)["entry"].map { |e| e["resource"]["id"] }).to eq([derived_id])
    end

    it "finds by date (effective time)" do
      subject_id = create_patient
      post "/Observation", params: valid_observation_payload(subject_id: subject_id), as: :json

      get "/Observation", params: { date: "ge2026-07-19", subject: "Patient/#{subject_id}" }

      expect(JSON.parse(response.body)["total"]).to eq(1)
    end

    it "excludes deleted resources from search results" do
      subject_id = create_patient
      post "/Observation", params: valid_observation_payload(subject_id: subject_id), as: :json
      id = JSON.parse(response.body)["id"]
      delete "/Observation/#{id}"

      get "/Observation", params: { _id: id }

      expect(JSON.parse(response.body)["total"]).to eq(0)
    end

    it "includes the referenced Patient via Observation:subject" do
      subject_id = create_patient
      post "/Observation", params: valid_observation_payload(subject_id: subject_id), as: :json
      id = JSON.parse(response.body)["id"]

      get "/Observation", params: { _id: id, _include: "Observation:subject" }

      bundle = JSON.parse(response.body)
      included = bundle["entry"].select { |entry| entry.dig("search", "mode") == "include" }
      expect(included.map { |entry| entry["resource"]["resourceType"] }).to eq(["Patient"])
      expect(included.first["resource"]["id"]).to eq(subject_id)
    end
  end
end
