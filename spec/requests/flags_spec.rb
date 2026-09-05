require "rails_helper"

RSpec.describe "Flags", type: :request do
  def create_patient
    post "/Patient", params: valid_patient_payload, as: :json
    JSON.parse(response.body)["id"]
  end

  def create_flag(patient_id, **overrides)
    post "/Flag", params: valid_flag_payload(subject_id: patient_id, **overrides), as: :json
    expect(response).to have_http_status(:created), "setup failed: #{response.body}"
    JSON.parse(response.body)["id"]
  end

  describe "POST /Flag" do
    it "creates and returns 201 with Location, ETag, and meta" do
      patient_id = create_patient

      post "/Flag", params: valid_flag_payload(subject_id: patient_id), as: :json

      expect(response).to have_http_status(:created)
      expect(response.content_type).to include("application/fhir+json")
      expect(response.headers["Location"]).to match(%r{/Flag/[\w-]+/_history/1\z})
      expect(response.headers["ETag"]).to eq('W/"1"')

      body = JSON.parse(response.body)
      expect(body["resourceType"]).to eq("Flag")
      # Flag は JP Core がプロファイルしない型なので基本定義が付く。
      expect(body["meta"]["profile"]).to eq(["http://hl7.org/fhir/StructureDefinition/Flag"])
    end

    it "returns 422 for a status outside the value set" do
      patient_id = create_patient

      post "/Flag", params: valid_flag_payload(subject_id: patient_id, status: "bogus"), as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "returns 422 when code is missing" do
      patient_id = create_patient
      payload = valid_flag_payload(subject_id: patient_id).except("code")

      post "/Flag", params: payload, as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "returns 422 when subject references a non-existent patient" do
      post "/Flag", params: valid_flag_payload(subject_id: "does-not-exist"), as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "GET /Flag/:id" do
    it "returns the resource" do
      patient_id = create_patient
      id = create_flag(patient_id)

      get "/Flag/#{id}"

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["code"]["coding"].first["code"]).to eq("fall")
    end

    it "returns 404 for an unknown id" do
      get "/Flag/does-not-exist"

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "PUT /Flag/:id" do
    it "updates with If-Match and rejects a stale version with 412" do
      patient_id = create_patient
      id = create_flag(patient_id)

      put "/Flag/#{id}",
          params: valid_flag_payload(subject_id: patient_id, status: "inactive",
                                     period: { "start" => "2026-09-01", "end" => "2026-09-05" }),
          headers: { "If-Match" => 'W/"1"' }, as: :json
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["meta"]["versionId"]).to eq("2")

      put "/Flag/#{id}", params: valid_flag_payload(subject_id: patient_id),
                         headers: { "If-Match" => 'W/"1"' }, as: :json
      expect(response).to have_http_status(:precondition_failed)
    end
  end

  describe "GET /Flag (search)" do
    it "finds by subject and by its patient alias" do
      patient_id = create_patient
      id = create_flag(patient_id)

      get "/Flag", params: { subject: "Patient/#{patient_id}" }
      by_subject = JSON.parse(response.body)

      get "/Flag", params: { patient: "Patient/#{patient_id}" }
      by_patient = JSON.parse(response.body)

      expect(by_subject["total"]).to eq(1)
      expect(by_patient["entry"].map { |e| e["resource"]["id"] }).to eq([id])
    end

    it "filters by status" do
      patient_id = create_patient
      active = create_flag(patient_id)
      create_flag(patient_id, status: "inactive")

      get "/Flag?patient=Patient/#{patient_id}&status=active"

      expect(JSON.parse(response.body)["entry"].map { |e| e["resource"]["id"] }).to eq([active])
    end

    it "filters by category" do
      patient_id = create_patient
      create_flag(patient_id)
      clinical = create_flag(patient_id, category: [
                               { "coding" => [{ "system" => "http://fhir-client.local/CodeSystem/flag-category",
                                                "code" => "clinical" }] }
                             ])

      get "/Flag?patient=Patient/#{patient_id}&category=clinical"

      expect(JSON.parse(response.body)["entry"].map { |e| e["resource"]["id"] }).to eq([clinical])
    end

    it "filters by the period via date" do
      patient_id = create_patient
      recent = create_flag(patient_id, period: { "start" => "2026-09-01" })
      create_flag(patient_id, period: { "start" => "2020-01-01", "end" => "2020-02-01" })

      get "/Flag?patient=Patient/#{patient_id}&date=ge2026-01-01"

      expect(JSON.parse(response.body)["entry"].map { |e| e["resource"]["id"] }).to eq([recent])
    end

    it "includes the referenced Patient via Flag:subject" do
      patient_id = create_patient
      id = create_flag(patient_id)

      get "/Flag", params: { _id: id, _include: "Flag:subject" }

      bundle = JSON.parse(response.body)
      included = bundle["entry"].select { |entry| entry.dig("search", "mode") == "include" }
      expect(included.map { |entry| entry["resource"]["resourceType"] }).to eq(["Patient"])
    end
  end

  # subject が Patient を指す単一列参照なので、患者コンパートメントに自動で入る。
  describe "Patient/$everything" do
    it "includes the patient's flags" do
      patient_id = create_patient
      id = create_flag(patient_id)

      get "/Patient/#{patient_id}/$everything"

      types = JSON.parse(response.body)["entry"].map { |e| e["resource"]["id"] }
      expect(types).to include(id)
    end
  end
end
