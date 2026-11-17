require "rails_helper"

RSpec.describe "FamilyMemberHistories", type: :request do
  def create_patient
    post "/Patient", params: valid_patient_payload, as: :json
    JSON.parse(response.body)["id"]
  end

  def create_history(patient_id, **overrides)
    post "/FamilyMemberHistory", params: valid_family_member_history_payload(patient_id: patient_id, **overrides), as: :json
    expect(response).to have_http_status(:created), "setup failed: #{response.body}"
    JSON.parse(response.body)["id"]
  end

  def result_ids
    JSON.parse(response.body).fetch("entry", []).map { |e| e["resource"]["id"] }
  end

  let(:patient_id) { create_patient }

  describe "POST /FamilyMemberHistory" do
    it "creates and returns 201 with Location, ETag, and the JP Core profile" do
      post "/FamilyMemberHistory", params: valid_family_member_history_payload(patient_id: patient_id), as: :json

      expect(response).to have_http_status(:created)
      expect(response.headers["Location"]).to match(%r{/FamilyMemberHistory/[\w-]+/_history/1\z})
      expect(response.headers["ETag"]).to eq('W/"1"')

      body = JSON.parse(response.body)
      expect(body["resourceType"]).to eq("FamilyMemberHistory")
      expect(body["meta"]["profile"]).to eq(["http://jpfhir.jp/fhir/core/StructureDefinition/JP_FamilyMemberHistory"])
    end

    it "returns 422 for an invalid status, a missing relationship, and an unknown patient" do
      post "/FamilyMemberHistory", params: valid_family_member_history_payload(patient_id: patient_id, status: "bogus"), as: :json
      expect(response).to have_http_status(:unprocessable_content)

      post "/FamilyMemberHistory", params: valid_family_member_history_payload(patient_id: patient_id).except("relationship"), as: :json
      expect(response).to have_http_status(:unprocessable_content)

      post "/FamilyMemberHistory", params: valid_family_member_history_payload(patient_id: "does-not-exist"), as: :json
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "read / update / delete" do
    it "reads, updates with If-Match, and deletes" do
      id = create_history(patient_id)

      get "/FamilyMemberHistory/#{id}"
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body).dig("relationship", "coding", 0, "code")).to eq("MTH")

      put "/FamilyMemberHistory/#{id}",
          params: valid_family_member_history_payload(patient_id: patient_id, status: "partial"),
          headers: { "If-Match" => 'W/"1"' }, as: :json
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["meta"]["versionId"]).to eq("2")

      delete "/FamilyMemberHistory/#{id}"
      get "/FamilyMemberHistory/#{id}"
      expect(response).to have_http_status(:gone)
    end

    it "returns 404 for an unknown id" do
      get "/FamilyMemberHistory/does-not-exist"

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GET /FamilyMemberHistory (search)" do
    let(:father) do
      { "coding" => [{ "system" => "http://terminology.hl7.org/CodeSystem/v3-RoleCode", "code" => "FTH" }] }
    end
    let(:male) { { "coding" => [{ "system" => "http://hl7.org/fhir/administrative-gender", "code" => "male" }] } }

    it "finds by patient and keeps other patients out" do
      id = create_history(patient_id)
      create_history(create_patient)

      get "/FamilyMemberHistory?patient=Patient/#{patient_id}"

      expect(result_ids).to eq([id])
    end

    it "filters by status, relationship, and sex" do
      mother = create_history(patient_id)
      fth = create_history(patient_id, status: "partial", relationship: father, sex: male)

      get "/FamilyMemberHistory?patient=Patient/#{patient_id}&status=partial"
      expect(result_ids).to eq([fth])

      get "/FamilyMemberHistory?patient=Patient/#{patient_id}&relationship=http://terminology.hl7.org/CodeSystem/v3-RoleCode%7CMTH"
      expect(result_ids).to eq([mother])

      get "/FamilyMemberHistory?patient=Patient/#{patient_id}&sex=male"
      expect(result_ids).to eq([fth])
    end

    it "finds by any condition's code or text" do
      id = create_history(patient_id)
      create_history(patient_id, condition: [{ "code" => { "text" => "高血圧" } }])

      get "/FamilyMemberHistory?patient=Patient/#{patient_id}&code=http://hl7.org/fhir/sid/icd-10%7CE11"
      expect(result_ids).to eq([id])

      # テキストは全 condition を連結した文字列への前方一致。先頭の病名はそのまま引ける。
      get "/FamilyMemberHistory?patient=Patient/#{patient_id}&code=#{Rack::Utils.escape('糖尿')}"
      expect(result_ids).to eq([id])

      # 2 件目以降の病名(text だけ)は :contains で引く。
      get "/FamilyMemberHistory?patient=Patient/#{patient_id}&code:contains=#{Rack::Utils.escape('難聴')}"
      expect(result_ids).to eq([id])
    end

    it "filters and sorts by the recorded date" do
      old = create_history(patient_id, date: "2020-01-01")
      recent = create_history(patient_id)

      get "/FamilyMemberHistory?patient=Patient/#{patient_id}&date=ge2026-01-01"
      expect(result_ids).to eq([recent])

      get "/FamilyMemberHistory?patient=Patient/#{patient_id}&_sort=date"
      expect(result_ids).to eq([old, recent])
    end

    it "includes the Patient and is reachable by _revinclude" do
      id = create_history(patient_id)

      get "/FamilyMemberHistory?_id=#{id}&_include=FamilyMemberHistory:patient"
      expect(result_ids).to eq([id, patient_id])

      get "/Patient?_id=#{patient_id}&_revinclude=FamilyMemberHistory:patient"
      expect(result_ids).to eq([patient_id, id])
    end
  end

  describe "patient compartment" do
    it "appears in $everything and in the compartment search" do
      id = create_history(patient_id)

      get "/Patient/#{patient_id}/$everything?_type=FamilyMemberHistory"
      expect(result_ids).to include(id)

      get "/Patient/#{patient_id}/FamilyMemberHistory"
      expect(result_ids).to eq([id])
    end

    it "is confined for a patient-context token" do
      mine = create_history(patient_id)
      theirs = create_history(create_patient)

      with_fhir_auth do
        headers = bearer_header(issue_patient_token(patient_id: patient_id))

        get "/FamilyMemberHistory", headers: headers
        expect(result_ids).to eq([mine])

        get "/FamilyMemberHistory/#{theirs}", headers: headers
        expect(response).to have_http_status(:not_found)
      end
    end
  end

  it "is advertised in the CapabilityStatement" do
    get "/metadata"

    resource = JSON.parse(response.body).dig("rest", 0, "resource").find { |r| r["type"] == "FamilyMemberHistory" }
    expect(resource["searchParam"].map { |p| p["name"] }).to include("patient", "relationship", "code", "date")
  end
end
