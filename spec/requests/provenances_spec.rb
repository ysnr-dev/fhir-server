require "rails_helper"

RSpec.describe "Provenances", type: :request do
  def create_patient
    post "/Patient", params: valid_patient_payload, as: :json
    JSON.parse(response.body)["id"]
  end

  def create_practitioner
    post "/Practitioner", params: valid_practitioner_payload, as: :json
    JSON.parse(response.body)["id"]
  end

  def create_service_request(subject_id)
    post "/ServiceRequest", params: valid_service_request_payload(subject_id: subject_id), as: :json
    JSON.parse(response.body)["id"]
  end

  def create_provenance(target_reference:, author_id:, **overrides)
    post "/Provenance",
         params: valid_provenance_payload(target_reference: target_reference, author_id: author_id, **overrides),
         as: :json
    JSON.parse(response.body)["id"]
  end

  def entry_ids(mode)
    JSON.parse(response.body)["entry"].to_a
        .select { |entry| entry.dig("search", "mode") == mode }
        .map { |entry| entry.dig("resource", "id") }
  end

  describe "POST /Provenance" do
    it "creates and returns 201 with Location, ETag, and meta" do
      author = create_practitioner
      order = create_service_request(create_patient)

      post "/Provenance",
           params: valid_provenance_payload(target_reference: "ServiceRequest/#{order}", author_id: author),
           as: :json

      expect(response).to have_http_status(:created)
      expect(response.content_type).to include("application/fhir+json")
      expect(response.headers["Location"]).to match(%r{/Provenance/[\w-]+/_history/1\z})
      expect(response.headers["ETag"]).to eq('W/"1"')

      body = JSON.parse(response.body)
      expect(body["resourceType"]).to eq("Provenance")
      expect(body["meta"]["profile"]).to eq(["http://hl7.org/fhir/StructureDefinition/Provenance"])
    end

    it "returns 422 when target is missing" do
      author = create_practitioner

      post "/Provenance",
           params: valid_provenance_payload(target_reference: "ServiceRequest/x", author_id: author).except("target"),
           as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Provenance.target is required")
    end

    it "returns 422 when recorded is not an instant" do
      author = create_practitioner

      post "/Provenance",
           params: valid_provenance_payload(target_reference: "ServiceRequest/x", author_id: author,
                                            recorded: "2026-09-01"),
           as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "read / update / delete lifecycle" do
    # 承認は「代行入力の Provenance に verifier と署名を足す」形で表す。
    it "records 代行入力 then 承認 through an update" do
      author = create_practitioner
      verifier = create_practitioner
      order = create_service_request(create_patient)
      id = create_provenance(target_reference: "ServiceRequest/#{order}", author_id: author)

      get "/Provenance/#{id}"
      expect(response).to have_http_status(:ok)
      approved = JSON.parse(response.body)
      approved["agent"] << verification_agent(verifier)
      approved["signature"] = [verification_signature(verifier)]

      put "/Provenance/#{id}", params: approved, as: :json

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["meta"]["versionId"]).to eq("2")
      expect(body["signature"].first["who"]["reference"]).to eq("Practitioner/#{verifier}")

      delete "/Provenance/#{id}"
      expect(response).to have_http_status(:no_content)

      get "/Provenance/#{id}"
      expect(response).to have_http_status(:gone)
    end
  end

  describe "search" do
    it "finds provenance by target" do
      author = create_practitioner
      patient = create_patient
      order = create_service_request(patient)
      other_order = create_service_request(patient)
      id = create_provenance(target_reference: "ServiceRequest/#{order}", author_id: author)
      create_provenance(target_reference: "ServiceRequest/#{other_order}", author_id: author)

      get "/Provenance", params: { target: "ServiceRequest/#{order}" }

      expect(JSON.parse(response.body)["total"]).to eq(1)
      expect(entry_ids("match")).to eq([id])
    end

    # target は異種の配列。オーダー 1 件の来歴は SR と その明細(MedicationRequest)の
    # 両方を指すので、どちらからでも同じ Provenance に辿り着けること。
    it "finds provenance by a non-default target type in the same array" do
      author = create_practitioner
      order = create_service_request(create_patient)
      id = create_provenance(
        target_reference: "ServiceRequest/#{order}", author_id: author,
        target: [{ "reference" => "ServiceRequest/#{order}" }, { "reference" => "MedicationRequest/mr1" }]
      )

      get "/Provenance", params: { target: "MedicationRequest/mr1" }

      expect(entry_ids("match")).to eq([id])
    end

    it "finds provenance by agent" do
      author = create_practitioner
      other = create_practitioner
      order = create_service_request(create_patient)
      id = create_provenance(target_reference: "ServiceRequest/#{order}", author_id: author)
      create_provenance(target_reference: "ServiceRequest/#{order}", author_id: other)

      get "/Provenance", params: { agent: "Practitioner/#{author}" }

      expect(entry_ids("match")).to eq([id])
    end

    it "finds provenance by agent-type" do
      author = create_practitioner
      order = create_service_request(create_patient)
      id = create_provenance(target_reference: "ServiceRequest/#{order}", author_id: author)

      get "/Provenance",
          params: { "agent-type" => "http://terminology.hl7.org/CodeSystem/provenance-participant-type|enterer" }

      expect(entry_ids("match")).to eq([id])
    end

    it "finds provenance by signature-type" do
      author = create_practitioner
      order = create_service_request(create_patient)
      id = create_provenance(target_reference: "ServiceRequest/#{order}", author_id: author,
                             signature: [verification_signature(author)])
      create_provenance(target_reference: "ServiceRequest/#{order}", author_id: author)

      get "/Provenance", params: { "signature-type" => "1.2.840.10065.1.12.1.5" }

      expect(entry_ids("match")).to eq([id])
    end

    it "filters by recorded" do
      author = create_practitioner
      order = create_service_request(create_patient)
      id = create_provenance(target_reference: "ServiceRequest/#{order}", author_id: author)
      create_provenance(target_reference: "ServiceRequest/#{order}", author_id: author,
                        recorded: "2026-08-01T10:00:00+09:00")

      get "/Provenance", params: { recorded: "2026-09-01" }

      expect(entry_ids("match")).to eq([id])
    end

    it "finds provenance by patient when the patient is one of the targets" do
      author = create_practitioner
      patient = create_patient
      id = create_provenance(target_reference: "Patient/#{patient}", author_id: author)

      get "/Provenance", params: { patient: "Patient/#{patient}" }

      expect(entry_ids("match")).to eq([id])
    end
  end

  describe "_include / _revinclude" do
    # オーダー画面の読み出し経路。オーダー本体と一緒に来歴を引く。
    it "includes the provenance with _revinclude=Provenance:target" do
      author = create_practitioner
      patient = create_patient
      order = create_service_request(patient)
      id = create_provenance(target_reference: "ServiceRequest/#{order}", author_id: author)
      create_provenance(target_reference: "ServiceRequest/#{create_service_request(patient)}", author_id: author)

      get "/ServiceRequest", params: { _id: order, _revinclude: "Provenance:target" }

      expect(entry_ids("match")).to eq([order])
      expect(entry_ids("include")).to eq([id])
    end

    it "includes the agent with _include=Provenance:agent" do
      author = create_practitioner
      order = create_service_request(create_patient)
      id = create_provenance(target_reference: "ServiceRequest/#{order}", author_id: author)

      get "/Provenance", params: { _id: id, _include: "Provenance:agent" }

      expect(entry_ids("match")).to eq([id])
      expect(entry_ids("include")).to eq([author])
    end
  end

  describe "_has" do
    # 「承認済みのオーダー」をオーダー側から引く。
    it "finds orders whose provenance has a verifier" do
      author = create_practitioner
      verifier = create_practitioner
      patient = create_patient
      approved_order = create_service_request(patient)
      create_service_request(patient)
      create_provenance(target_reference: "ServiceRequest/#{approved_order}", author_id: author,
                        agent: valid_provenance_payload(target_reference: "x", author_id: author)["agent"] +
                               [verification_agent(verifier)])

      get "/ServiceRequest",
          params: { "_has:Provenance:target:agent-type" =>
                      "http://terminology.hl7.org/CodeSystem/provenance-participant-type|verifier" }

      expect(entry_ids("match")).to eq([approved_order])
    end
  end

  describe "CapabilityStatement" do
    it "advertises Provenance with its search parameters and revinclude" do
      get "/metadata"

      resources = JSON.parse(response.body)["rest"].first["resource"]
      provenance = resources.find { |r| r["type"] == "Provenance" }

      expect(provenance["profile"]).to eq("http://hl7.org/fhir/StructureDefinition/Provenance")
      expect(provenance["searchParam"].map { |p| p["name"] })
        .to include("target", "patient", "agent", "recorded", "agent-type", "signature-type")

      service_request = resources.find { |r| r["type"] == "ServiceRequest" }
      expect(service_request["searchRevInclude"]).to include("Provenance:target")
    end
  end
end
