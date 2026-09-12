require "rails_helper"

RSpec.describe "Goals", type: :request do
  def create_patient
    post "/Patient", params: valid_patient_payload, as: :json
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

  describe "POST /Goal" do
    it "creates and returns 201 with Location, ETag, and meta" do
      patient_id = create_patient

      post "/Goal", params: valid_goal_payload(subject_id: patient_id), as: :json

      expect(response).to have_http_status(:created)
      expect(response.content_type).to include("application/fhir+json")
      expect(response.headers["Location"]).to match(%r{/Goal/[\w-]+/_history/1\z})
      expect(response.headers["ETag"]).to eq('W/"1"')

      body = JSON.parse(response.body)
      expect(body["resourceType"]).to eq("Goal")
      # Goal は JP Core がプロファイルしない型なので基本定義が付く。
      expect(body["meta"]["profile"]).to eq(["http://hl7.org/fhir/StructureDefinition/Goal"])
    end

    it "returns 422 for a lifecycleStatus outside the value set" do
      patient_id = create_patient

      post "/Goal", params: valid_goal_payload(subject_id: patient_id, lifecycleStatus: "bogus"), as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "returns 422 when description is missing" do
      patient_id = create_patient
      payload = valid_goal_payload(subject_id: patient_id).except("description")

      post "/Goal", params: payload, as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "returns 422 when subject references a non-existent patient" do
      post "/Goal", params: valid_goal_payload(subject_id: "does-not-exist"), as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end

    # achievementStatus の束縛は preferred。ePath の達成状態のように、ガイドが
    # 独自のコード体系を使う。
    it "accepts an achievementStatus from a non-HL7 code system" do
      patient_id = create_patient

      post "/Goal", params: valid_goal_payload(
        subject_id: patient_id,
        achievementStatus: {
          "coding" => [{ "system" => "http://e-path.jp/fhir/ePath/CodeSystem/EPathStateOfAchievementCS",
                         "code" => "2", "display" => "未達成（バリアンス）" }]
        }
      ), as: :json

      expect(response).to have_http_status(:created)
    end
  end

  describe "GET /Goal/:id" do
    it "returns the resource" do
      patient_id = create_patient
      id = create_goal(patient_id)

      get "/Goal/#{id}"

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["description"]["text"]).to eq("疼痛がコントロールできる")
    end

    it "returns 404 for an unknown id" do
      get "/Goal/does-not-exist"

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "PUT /Goal/:id" do
    it "updates with If-Match and rejects a stale version with 412" do
      patient_id = create_patient
      id = create_goal(patient_id)

      put "/Goal/#{id}",
          params: valid_goal_payload(subject_id: patient_id, lifecycleStatus: "completed"),
          headers: { "If-Match" => 'W/"1"' }, as: :json
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["meta"]["versionId"]).to eq("2")

      put "/Goal/#{id}", params: valid_goal_payload(subject_id: patient_id),
                         headers: { "If-Match" => 'W/"1"' }, as: :json
      expect(response).to have_http_status(:precondition_failed)
    end
  end

  describe "GET /Goal (search)" do
    it "finds by subject and by its patient alias" do
      patient_id = create_patient
      id = create_goal(patient_id)

      get "/Goal", params: { subject: "Patient/#{patient_id}" }
      expect(JSON.parse(response.body)["total"]).to eq(1)

      get "/Goal", params: { patient: "Patient/#{patient_id}" }
      expect(ids_of(response.body)).to eq([id])
    end

    it "filters by lifecycle-status" do
      patient_id = create_patient
      active = create_goal(patient_id)
      create_goal(patient_id, lifecycleStatus: "completed")

      get "/Goal", params: { patient: "Patient/#{patient_id}", "lifecycle-status" => "active" }

      expect(ids_of(response.body)).to eq([active])
    end

    # アウトカムが達成できたか(未達成 = バリアンス)で絞る。ePath のコード体系でも
    # 索引されるので、system まで書いても引ける。
    it "filters by achievement-status, with or without its system" do
      patient_id = create_patient
      create_goal(patient_id)
      variance = create_goal(patient_id, achievementStatus: {
                               "coding" => [{ "system" => "http://e-path.jp/fhir/ePath/CodeSystem/EPathStateOfAchievementCS",
                                              "code" => "2" }]
                             })

      get "/Goal", params: { patient: "Patient/#{patient_id}", "achievement-status" => "2" }
      expect(ids_of(response.body)).to eq([variance])

      get "/Goal", params: {
        patient: "Patient/#{patient_id}",
        "achievement-status" => "http://e-path.jp/fhir/ePath/CodeSystem/EPathStateOfAchievementCS|2"
      }
      expect(ids_of(response.body)).to eq([variance])
    end

    it "filters by category" do
      patient_id = create_patient
      create_goal(patient_id)
      nursing = create_goal(patient_id, category: [
                              { "coding" => [{ "system" => "http://terminology.hl7.org/CodeSystem/goal-category",
                                               "code" => "nursing" }] }
                            ])

      get "/Goal", params: { patient: "Patient/#{patient_id}", category: "nursing" }

      expect(ids_of(response.body)).to eq([nursing])
    end

    it "filters by start-date" do
      patient_id = create_patient
      recent = create_goal(patient_id, startDate: "2026-09-01")
      create_goal(patient_id, startDate: "2020-01-01")

      get "/Goal", params: { patient: "Patient/#{patient_id}", "start-date" => "ge2026-01-01" }

      expect(ids_of(response.body)).to eq([recent])
    end

    it "includes the referenced Patient via Goal:subject" do
      patient_id = create_patient
      id = create_goal(patient_id)

      get "/Goal", params: { _id: id, _include: "Goal:subject" }

      bundle = JSON.parse(response.body)
      included = bundle["entry"].select { |entry| entry.dig("search", "mode") == "include" }
      expect(included.map { |entry| entry["resource"]["resourceType"] }).to eq(["Patient"])
    end
  end

  # subject が Patient を指す単一列参照なので、患者コンパートメントに自動で入る。
  describe "Patient/$everything" do
    it "includes the patient's goals" do
      patient_id = create_patient
      id = create_goal(patient_id)

      get "/Patient/#{patient_id}/$everything"

      expect(ids_of(response.body)).to include(id)
    end
  end
end
