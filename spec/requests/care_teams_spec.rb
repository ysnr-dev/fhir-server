require "rails_helper"

RSpec.describe "CareTeams", type: :request do
  def create_patient
    post "/Patient", params: valid_patient_payload, as: :json
    JSON.parse(response.body)["id"]
  end

  def create_team(**overrides)
    post "/CareTeam", params: valid_care_team_payload(**overrides), as: :json
    expect(response).to have_http_status(:created), "setup failed: #{response.body}"
    JSON.parse(response.body)["id"]
  end

  def ids_of(body)
    JSON.parse(body)["entry"].to_a.reject { |e| e.dig("search", "mode") == "include" }.map { |e| e["resource"]["id"] }
  end

  describe "POST /CareTeam" do
    it "creates an organizational team (no subject) and returns 201 with meta" do
      post "/CareTeam", params: valid_care_team_payload, as: :json

      expect(response).to have_http_status(:created)
      expect(response.headers["Location"]).to match(%r{/CareTeam/[\w-]+/_history/1\z})
      body = JSON.parse(response.body)
      expect(body["resourceType"]).to eq("CareTeam")
      expect(body["meta"]["profile"]).to eq(["http://hl7.org/fhir/StructureDefinition/CareTeam"])
    end

    it "returns 422 for a status outside the value set" do
      post "/CareTeam", params: valid_care_team_payload(status: "bogus"), as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "returns 422 when subject references a non-existent patient" do
      post "/CareTeam", params: valid_care_team_payload(subject_id: "does-not-exist"), as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "PUT /CareTeam/:id" do
    it "updates with If-Match and rejects a stale version with 412" do
      id = create_team

      put "/CareTeam/#{id}", params: valid_care_team_payload(status: "inactive"),
                             headers: { "If-Match" => 'W/"1"' }, as: :json
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["meta"]["versionId"]).to eq("2")

      put "/CareTeam/#{id}", params: valid_care_team_payload, headers: { "If-Match" => 'W/"1"' }, as: :json
      expect(response).to have_http_status(:precondition_failed)
    end
  end

  describe "GET /CareTeam (search)" do
    it "filters by status, category and name" do
      nst = create_team
      create_team(status: "inactive", name: "旧チーム")
      ict = create_team(name: "感染対策チーム", category: [
                          { "coding" => [{ "system" => CareTeamPayloadHelper::KIND_SYSTEM, "code" => "ict" }] }
                        ])

      get "/CareTeam", params: { status: "active", _sort: "_id" }
      expect(ids_of(response.body)).to match_array([nst, ict])

      get "/CareTeam", params: { category: "ict" }
      expect(ids_of(response.body)).to eq([ict])

      get "/CareTeam", params: { name: "感染" }
      expect(ids_of(response.body)).to eq([ict])
    end

    it "finds the teams a practitioner belongs to via participant, and includes the members" do
      mine = create_team
      create_team(name: "別のチーム", participant: [{ "member" => { "reference" => "Practitioner/other" } }])

      get "/CareTeam", params: { participant: "Practitioner/ns-1" }
      expect(ids_of(response.body)).to eq([mine])

      get "/CareTeam", params: { participant: "ns-1" }
      expect(ids_of(response.body)).to eq([mine])
    end

    it "finds a patient care team by subject and its patient alias" do
      patient_id = create_patient
      id = create_team(subject_id: patient_id, name: "患者のケアチーム")
      create_team

      get "/CareTeam", params: { patient: "Patient/#{patient_id}" }
      expect(ids_of(response.body)).to eq([id])

      get "/CareTeam", params: { subject: "Patient/#{patient_id}", _include: "CareTeam:subject" }
      included = JSON.parse(response.body)["entry"].select { |entry| entry.dig("search", "mode") == "include" }
      expect(included.map { |entry| entry["resource"]["resourceType"] }).to eq(["Patient"])
    end
  end

  # チーム依頼(ServiceRequest.performer = CareTeam)と Task.owner = CareTeam が引けること。
  describe "references from ServiceRequest and Task" do
    it "finds orders addressed to a team by performer and includes the team" do
      patient_id = create_patient
      team_id = create_team
      post "/ServiceRequest",
           params: valid_service_request_payload(subject_id: patient_id,
                                                 "performer" => [{ "reference" => "CareTeam/#{team_id}" }]),
           as: :json
      expect(response).to have_http_status(:created), response.body
      order_id = JSON.parse(response.body)["id"]
      post "/ServiceRequest", params: valid_service_request_payload(subject_id: patient_id), as: :json

      get "/ServiceRequest", params: { subject: "Patient/#{patient_id}", performer: "CareTeam/#{team_id}",
                                        _include: "ServiceRequest:performer" }
      expect(ids_of(response.body)).to eq([order_id])
      included = JSON.parse(response.body)["entry"].select { |e| e.dig("search", "mode") == "include" }
      expect(included.map { |e| e["resource"]["resourceType"] }).to eq(["CareTeam"])
    end

    it "finds tasks owned by a team" do
      patient_id = create_patient
      team_id = create_team
      post "/Task", params: valid_task_payload(subject_id: patient_id, "owner" => { "reference" => "CareTeam/#{team_id}" }), as: :json
      expect(response).to have_http_status(:created), response.body
      task_id = JSON.parse(response.body)["id"]

      get "/Task", params: { owner: "CareTeam/#{team_id}" }
      expect(ids_of(response.body)).to eq([task_id])
    end
  end
end
