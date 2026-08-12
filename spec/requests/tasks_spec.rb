require "rails_helper"

RSpec.describe "Tasks", type: :request do
  def create_patient
    post "/Patient", params: valid_patient_payload, as: :json
    JSON.parse(response.body)["id"]
  end

  def create_practitioner
    post "/Practitioner", params: valid_practitioner_payload, as: :json
    JSON.parse(response.body)["id"]
  end

  def create_service_request(subject_id:)
    post "/ServiceRequest", params: valid_service_request_payload(subject_id: subject_id), as: :json
    JSON.parse(response.body)["id"]
  end

  def create_task(**args)
    post "/Task", params: valid_task_payload(**args), as: :json
    expect(response).to have_http_status(:created), "setup failed: #{response.body}"
    JSON.parse(response.body)["id"]
  end

  describe "POST /Task" do
    it "creates and returns 201 with Location, ETag, and meta" do
      patient_id = create_patient

      post "/Task", params: valid_task_payload(for_id: patient_id), as: :json

      expect(response).to have_http_status(:created)
      expect(response.content_type).to include("application/fhir+json")
      expect(response.headers["Location"]).to match(%r{/Task/[\w-]+/_history/1\z})
      expect(response.headers["ETag"]).to eq('W/"1"')

      body = JSON.parse(response.body)
      expect(body["resourceType"]).to eq("Task")
      # JP Core does not profile Task, so the bare HL7 base profile is stamped.
      expect(body["meta"]["profile"]).to eq(["http://hl7.org/fhir/StructureDefinition/Task"])
    end

    it "returns 422 for a status outside the task-status ValueSet" do
      post "/Task", params: valid_task_payload(status: "revoked"), as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "returns 422 when lastModified precedes authoredOn (inv-1)" do
      post "/Task", params: valid_task_payload(lastModified: "2026-08-12T08:00:00+09:00"), as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "returns 422 when for references a non-existent patient" do
      post "/Task", params: valid_task_payload(for_id: "does-not-exist"), as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "GET /Task/:id" do
    it "returns the resource" do
      id = create_task

      get "/Task/#{id}"

      expect(response).to have_http_status(:ok)
    end

    it "returns 404 for an unknown id" do
      get "/Task/does-not-exist"

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "PUT and DELETE" do
    it "advances the workflow status and then deletes" do
      id = create_task

      put "/Task/#{id}", params: valid_task_payload(status: "completed"), as: :json
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["meta"]["versionId"]).to eq("2")

      delete "/Task/#{id}"
      expect(response).to have_http_status(:no_content)

      get "/Task/#{id}"
      expect(response).to have_http_status(:gone)
    end
  end

  describe "GET /Task (search)" do
    it "finds by identifier" do
      create_task

      get "/Task", params: { identifier: "TSK1" }

      bundle = JSON.parse(response.body)
      expect(bundle["type"]).to eq("searchset")
      expect(bundle["total"]).to eq(1)
    end

    it "finds by status, intent, and priority" do
      create_task

      get "/Task", params: { status: "in-progress", intent: "order", priority: "routine" }

      expect(JSON.parse(response.body)["total"]).to eq(1)
    end

    # The workflow question status alone cannot answer: FHIR's status is a fixed
    # ValueSet, businessStatus carries the site's own stage codes.
    it "finds by business-status, including system|code" do
      create_task

      get "/Task", params: { "business-status" => "http://example.org/CodeSystem/lab-workflow|collected" }

      expect(JSON.parse(response.body)["total"]).to eq(1)
    end

    it "finds by group-identifier" do
      create_task

      get "/Task", params: { "group-identifier" => "http://example.org/order-group|ORD-2026-0001" }

      expect(JSON.parse(response.body)["total"]).to eq(1)
    end

    it "finds by performer (performerType)" do
      create_task

      get "/Task", params: { performer: "nurse" }

      expect(JSON.parse(response.body)["total"]).to eq(1)
    end

    it "finds by code and by its text" do
      create_task

      get "/Task", params: { code: "fulfill" }
      expect(JSON.parse(response.body)["total"]).to eq(1)

      get "/Task", params: { code: "検査オーダー" }
      expect(JSON.parse(response.body)["total"]).to eq(1)
    end

    it "finds by patient (the alias of subject / Task.for)" do
      patient_id = create_patient
      create_task(for_id: patient_id)
      create_task(for_id: create_patient)

      get "/Task", params: { patient: "Patient/#{patient_id}" }

      expect(JSON.parse(response.body)["total"]).to eq(1)
    end

    it "finds by owner, the assignee's worklist query" do
      owner_id = create_practitioner
      create_task(owner_id: owner_id)
      create_task

      get "/Task", params: { owner: "Practitioner/#{owner_id}", status: "in-progress" }

      expect(JSON.parse(response.body)["total"]).to eq(1)
    end

    it "finds by requester" do
      requester_id = create_practitioner
      create_task(requester_id: requester_id)

      get "/Task", params: { requester: "Practitioner/#{requester_id}" }

      expect(JSON.parse(response.body)["total"]).to eq(1)
    end

    it "finds by focus and by based-on, both pointing at the ServiceRequest" do
      patient_id = create_patient
      service_request_id = create_service_request(subject_id: patient_id)
      create_task(for_id: patient_id, service_request_id: service_request_id)
      create_task(for_id: patient_id)

      get "/Task", params: { focus: "ServiceRequest/#{service_request_id}" }
      expect(JSON.parse(response.body)["total"]).to eq(1)

      get "/Task", params: { "based-on" => "ServiceRequest/#{service_request_id}" }
      expect(JSON.parse(response.body)["total"]).to eq(1)
    end

    it "finds sub-tasks by part-of" do
      parent_id = create_task
      create_task(part_of_id: parent_id)

      get "/Task", params: { "part-of" => "Task/#{parent_id}" }

      expect(JSON.parse(response.body)["total"]).to eq(1)
    end

    it "finds by authored-on and modified" do
      create_task

      get "/Task", params: { "authored-on" => "2026-08-12", modified: "ge2026-08-12T01:00:00Z" }

      expect(JSON.parse(response.body)["total"]).to eq(1)
    end

    # period matches Task.executionPeriod by containment, like Encounter:date.
    it "finds by period containing the execution period" do
      create_task

      get "/Task", params: { period: "2026-08-12" }
      expect(JSON.parse(response.body)["total"]).to eq(1)

      get "/Task", params: { period: "2026-08-13" }
      expect(JSON.parse(response.body)["total"]).to eq(0)
    end

    it "separates parent tasks from sub-tasks with part-of:missing" do
      parent_id = create_task
      create_task(part_of_id: parent_id)

      get "/Task", params: { "part-of:missing" => "true" }

      expect(JSON.parse(response.body)["total"]).to eq(1)
    end

    # The workflow's headline query: given an order, what is being done about it.
    it "supports chained search from Task to the ServiceRequest's patient" do
      patient_id = create_patient
      service_request_id = create_service_request(subject_id: patient_id)
      create_task(for_id: patient_id, service_request_id: service_request_id)

      get "/Task", params: { "subject:Patient._id" => patient_id }

      expect(JSON.parse(response.body)["total"]).to eq(1)
    end

    it "answers 'which orders have a task' with _has on ServiceRequest" do
      patient_id = create_patient
      service_request_id = create_service_request(subject_id: patient_id)
      create_service_request(subject_id: patient_id)
      create_task(for_id: patient_id, service_request_id: service_request_id)

      get "/ServiceRequest", params: { "_has:Task:focus:status" => "in-progress" }

      bundle = JSON.parse(response.body)
      expect(bundle["total"]).to eq(1)
      expect(bundle["entry"].first["resource"]["id"]).to eq(service_request_id)
    end
  end

  describe "_include / _revinclude" do
    it "includes the ServiceRequest via Task:focus" do
      patient_id = create_patient
      service_request_id = create_service_request(subject_id: patient_id)
      id = create_task(for_id: patient_id, service_request_id: service_request_id)

      get "/Task", params: { _id: id, _include: "Task:focus" }

      bundle = JSON.parse(response.body)
      included = bundle["entry"].select { |entry| entry.dig("search", "mode") == "include" }
      expect(included.map { |entry| entry["resource"]["resourceType"] }).to eq(["ServiceRequest"])
    end

    # The order screen's one-request view: the order plus its workflow progress.
    it "pulls a ServiceRequest's tasks with _revinclude=Task:based-on" do
      patient_id = create_patient
      service_request_id = create_service_request(subject_id: patient_id)
      create_task(for_id: patient_id, service_request_id: service_request_id)

      get "/ServiceRequest", params: { _id: service_request_id, _revinclude: "Task:based-on" }

      bundle = JSON.parse(response.body)
      included = bundle["entry"].select { |entry| entry.dig("search", "mode") == "include" }
      expect(included.map { |entry| entry["resource"]["resourceType"] }).to eq(["Task"])
    end
  end

  describe "patient compartment" do
    it "returns the patient's tasks from Patient/:id/$everything" do
      patient_id = create_patient
      create_task(for_id: patient_id)
      create_task(for_id: create_patient)

      get "/Patient/#{patient_id}/$everything"

      types = JSON.parse(response.body)["entry"].map { |entry| entry["resource"]["resourceType"] }
      expect(types).to include("Task")
      expect(types.count("Task")).to eq(1)
    end
  end

  describe "capability statement" do
    it "advertises Task with the base HL7 profile and its workflow search params" do
      get "/metadata"

      resource = JSON.parse(response.body)["rest"].first["resource"].find { |r| r["type"] == "Task" }
      expect(resource["profile"]).to eq("http://hl7.org/fhir/StructureDefinition/Task")
      expect(resource["searchParam"].map { |p| p["name"] })
        .to include("status", "intent", "business-status", "owner", "focus", "based-on", "part-of", "modified")
      expect(resource["searchInclude"]).to include("Task:focus", "Task:based-on")
    end

    it "advertises Task:based-on as a ServiceRequest revinclude" do
      get "/metadata"

      resource = JSON.parse(response.body)["rest"].first["resource"].find { |r| r["type"] == "ServiceRequest" }
      expect(resource["searchRevInclude"]).to include("Task:based-on", "Task:focus")
    end
  end
end
