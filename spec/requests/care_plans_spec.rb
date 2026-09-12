require "rails_helper"

RSpec.describe "CarePlans", type: :request do
  def create_patient
    post "/Patient", params: valid_patient_payload, as: :json
    JSON.parse(response.body)["id"]
  end

  def create_care_plan(patient_id, **overrides)
    post "/CarePlan", params: valid_care_plan_payload(subject_id: patient_id, **overrides), as: :json
    expect(response).to have_http_status(:created), "setup failed: #{response.body}"
    JSON.parse(response.body)["id"]
  end

  def create_goal(patient_id, **overrides)
    post "/Goal", params: valid_goal_payload(subject_id: patient_id, **overrides), as: :json
    expect(response).to have_http_status(:created), "setup failed: #{response.body}"
    JSON.parse(response.body)["id"]
  end

  def ids_of(body)
    JSON.parse(body)["entry"].to_a.map { |entry| entry["resource"]["id"] }
  end

  describe "POST /CarePlan" do
    it "creates and returns 201 with Location, ETag, and meta" do
      patient_id = create_patient

      post "/CarePlan", params: valid_care_plan_payload(subject_id: patient_id), as: :json

      expect(response).to have_http_status(:created)
      expect(response.content_type).to include("application/fhir+json")
      expect(response.headers["Location"]).to match(%r{/CarePlan/[\w-]+/_history/1\z})
      expect(response.headers["ETag"]).to eq('W/"1"')

      body = JSON.parse(response.body)
      expect(body["resourceType"]).to eq("CarePlan")
      # CarePlan は JP Core がプロファイルしない型なので基本定義が付く。
      expect(body["meta"]["profile"]).to eq(["http://hl7.org/fhir/StructureDefinition/CarePlan"])
    end

    it "returns 422 for a status or intent outside the value set" do
      patient_id = create_patient

      post "/CarePlan", params: valid_care_plan_payload(subject_id: patient_id, status: "bogus"), as: :json
      expect(response).to have_http_status(:unprocessable_content)

      post "/CarePlan", params: valid_care_plan_payload(subject_id: patient_id, intent: "bogus"), as: :json
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "returns 422 when subject references a non-existent patient" do
      post "/CarePlan", params: valid_care_plan_payload(subject_id: "does-not-exist"), as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "GET /CarePlan/:id" do
    it "returns the resource" do
      patient_id = create_patient
      id = create_care_plan(patient_id)

      get "/CarePlan/#{id}"

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["intent"]).to eq("plan")
    end

    it "returns 404 for an unknown id" do
      get "/CarePlan/does-not-exist"

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "PUT /CarePlan/:id" do
    it "updates with If-Match and rejects a stale version with 412" do
      patient_id = create_patient
      id = create_care_plan(patient_id)

      put "/CarePlan/#{id}",
          params: valid_care_plan_payload(subject_id: patient_id, status: "completed",
                                          period: { "start" => "2026-09-01", "end" => "2026-09-05" }),
          headers: { "If-Match" => 'W/"1"' }, as: :json
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["meta"]["versionId"]).to eq("2")

      put "/CarePlan/#{id}", params: valid_care_plan_payload(subject_id: patient_id),
                             headers: { "If-Match" => 'W/"1"' }, as: :json
      expect(response).to have_http_status(:precondition_failed)
    end
  end

  describe "GET /CarePlan (search)" do
    it "finds by subject and by its patient alias" do
      patient_id = create_patient
      id = create_care_plan(patient_id)

      get "/CarePlan", params: { subject: "Patient/#{patient_id}" }
      expect(JSON.parse(response.body)["total"]).to eq(1)

      get "/CarePlan", params: { patient: "Patient/#{patient_id}" }
      expect(ids_of(response.body)).to eq([id])
    end

    it "filters by status and intent" do
      patient_id = create_patient
      active = create_care_plan(patient_id)
      create_care_plan(patient_id, status: "completed")

      get "/CarePlan?patient=Patient/#{patient_id}&status=active"
      expect(ids_of(response.body)).to eq([active])

      get "/CarePlan?patient=Patient/#{patient_id}&intent=plan"
      expect(ids_of(response.body).size).to eq(2)
    end

    # category は 0..* で、意味のある coding が先頭とは限らないため resource_tokens で
    # 引く。どの coding でも当たる。
    it "filters by any category coding" do
      patient_id = create_patient
      create_care_plan(patient_id)
      outcome = create_care_plan(patient_id, category: [
                                   { "coding" => [{ "system" => "http://e-path.jp/fhir/ePath/CodeSystem/EPathBOMOutcomeCategoryCS",
                                                    "code" => "H" }] },
                                   { "coding" => [{ "system" => "http://e-path.jp/fhir/ePath/CodeSystem/EPathBOMOutcomeCodeCS",
                                                    "code" => "O00470" }] }
                                 ])

      get "/CarePlan?patient=Patient/#{patient_id}&category=O00470"
      expect(ids_of(response.body)).to eq([outcome])

      get "/CarePlan?patient=Patient/#{patient_id}&category=H"
      expect(ids_of(response.body)).to eq([outcome])
    end

    it "filters by the period via date" do
      patient_id = create_patient
      recent = create_care_plan(patient_id, period: { "start" => "2026-09-01" })
      create_care_plan(patient_id, period: { "start" => "2020-01-01", "end" => "2020-02-01" })

      get "/CarePlan?patient=Patient/#{patient_id}&date=ge2026-01-01"

      expect(ids_of(response.body)).to eq([recent])
    end

    it "filters by the definition it was instantiated from" do
      patient_id = create_patient
      applied = create_care_plan(patient_id,
                                 instantiatesUri: ["http://fhir-client.local/pathway/900001"])
      create_care_plan(patient_id, instantiatesUri: ["http://fhir-client.local/pathway/900002"])

      get "/CarePlan", params: { patient: "Patient/#{patient_id}",
                                 "instantiates-uri" => "http://fhir-client.local/pathway/900001" }

      expect(ids_of(response.body)).to eq([applied])
    end

    # クリニカルパスの適用は CarePlan の木で表す。子孫は祖先すべてを partOf に並べるので、
    # 根は part-of:missing=true、木全体は part-of=適用 で引ける。
    describe "the plan tree (part-of)" do
      it "returns only the roots with part-of:missing=true, and the whole tree by the root" do
        patient_id = create_patient
        apply = create_care_plan(patient_id, title: "適用")
        event = create_care_plan(patient_id, title: "入院日",
                                             partOf: [{ "reference" => "CarePlan/#{apply}" }])
        unit = create_care_plan(patient_id, title: "OAT ユニット",
                                            partOf: [{ "reference" => "CarePlan/#{apply}" },
                                                     { "reference" => "CarePlan/#{event}" }])

        get "/CarePlan", params: { patient: "Patient/#{patient_id}", "part-of:missing" => "true" }
        expect(ids_of(response.body)).to eq([apply])

        get "/CarePlan", params: { "part-of" => "CarePlan/#{apply}" }
        expect(ids_of(response.body)).to contain_exactly(event, unit)

        get "/CarePlan", params: { "part-of" => "CarePlan/#{event}" }
        expect(ids_of(response.body)).to eq([unit])
      end
    end

    it "includes the referenced Patient and Goals" do
      patient_id = create_patient
      goal_id = create_goal(patient_id)
      id = create_care_plan(patient_id, goal: [{ "reference" => "Goal/#{goal_id}" }])

      # _include は繰り返しの問い合わせパラメータ(生のクエリ文字列で解釈される)。
      get "/CarePlan?_id=#{id}&_include=CarePlan:subject&_include=CarePlan:goal"

      bundle = JSON.parse(response.body)
      included = bundle["entry"].select { |entry| entry.dig("search", "mode") == "include" }
      expect(included.map { |entry| entry["resource"]["resourceType"] }).to contain_exactly("Patient", "Goal")
    end

    # パスのタスクは依頼を経ずに計画から直に実施されるので、実施記録は CarePlan を
    # basedOn で指す。計画の検索に _revinclude を添えると実施まで 1 リクエストで揃う。
    it "pulls the Procedures performed for the plan via _revinclude" do
      patient_id = create_patient
      id = create_care_plan(patient_id)
      post "/Procedure", params: valid_procedure_payload(subject_id: patient_id,
                                                         basedOn: [{ "reference" => "CarePlan/#{id}" }]),
                         as: :json
      expect(response).to have_http_status(:created), response.body
      procedure_id = JSON.parse(response.body)["id"]

      get "/CarePlan", params: { _id: id, _revinclude: "Procedure:based-on" }

      bundle = JSON.parse(response.body)
      included = bundle["entry"].select { |entry| entry.dig("search", "mode") == "include" }
      expect(included.map { |entry| entry["resource"]["id"] }).to eq([procedure_id])
    end
  end

  # subject が Patient を指す単一列参照なので、患者コンパートメントに自動で入る。
  describe "Patient/$everything" do
    it "includes the patient's care plans" do
      patient_id = create_patient
      id = create_care_plan(patient_id)

      get "/Patient/#{patient_id}/$everything"

      expect(ids_of(response.body)).to include(id)
    end
  end
end
