require "rails_helper"

RSpec.describe "Procedures", type: :request do
  def create_patient
    post "/Patient", params: valid_patient_payload, as: :json
    JSON.parse(response.body)["id"]
  end

  describe "POST /Procedure" do
    it "creates and returns 201 with Location, ETag, and meta" do
      subject_id = create_patient

      post "/Procedure", params: valid_procedure_payload(subject_id: subject_id), as: :json

      expect(response).to have_http_status(:created)
      expect(response.content_type).to include("application/fhir+json")
      expect(response.headers["Location"]).to match(%r{/Procedure/[\w-]+/_history/1\z})
      expect(response.headers["ETag"]).to eq('W/"1"')

      body = JSON.parse(response.body)
      expect(body["resourceType"]).to eq("Procedure")
      expect(body["meta"]["profile"]).to eq(["http://jpfhir.jp/fhir/core/StructureDefinition/JP_Procedure"])
    end

    it "returns 422 when status is missing" do
      subject_id = create_patient

      post "/Procedure", params: valid_procedure_payload(subject_id: subject_id).except("status"), as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "returns 422 for an invalid status" do
      subject_id = create_patient

      post "/Procedure", params: valid_procedure_payload(subject_id: subject_id, status: "bogus"), as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "returns 422 when subject references a non-existent patient" do
      post "/Procedure", params: valid_procedure_payload(subject_id: "does-not-exist"), as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "GET /Procedure/:id" do
    it "returns the resource" do
      subject_id = create_patient
      post "/Procedure", params: valid_procedure_payload(subject_id: subject_id), as: :json
      id = JSON.parse(response.body)["id"]

      get "/Procedure/#{id}"

      expect(response).to have_http_status(:ok)
    end

    it "returns 404 for an unknown id" do
      get "/Procedure/does-not-exist"

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "PUT and DELETE" do
    it "updates and then deletes" do
      subject_id = create_patient
      post "/Procedure", params: valid_procedure_payload(subject_id: subject_id), as: :json
      id = JSON.parse(response.body)["id"]

      put "/Procedure/#{id}", params: valid_procedure_payload(subject_id: subject_id, status: "entered-in-error"), as: :json
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["meta"]["versionId"]).to eq("2")

      delete "/Procedure/#{id}"
      expect(response).to have_http_status(:no_content)

      get "/Procedure/#{id}"
      expect(response).to have_http_status(:gone)
    end
  end

  describe "GET /Procedure (search)" do
    it "finds by subject reference" do
      subject_id = create_patient
      post "/Procedure", params: valid_procedure_payload(subject_id: subject_id), as: :json

      get "/Procedure", params: { subject: "Patient/#{subject_id}" }

      bundle = JSON.parse(response.body)
      expect(bundle["type"]).to eq("searchset")
      expect(bundle["total"]).to eq(1)
    end

    it "finds by code" do
      subject_id = create_patient
      post "/Procedure", params: valid_procedure_payload(subject_id: subject_id), as: :json

      get "/Procedure", params: { code: "80146002" }

      expect(JSON.parse(response.body)["total"]).to be >= 1
    end

    it "includes the referenced Patient via Procedure:subject" do
      subject_id = create_patient
      post "/Procedure", params: valid_procedure_payload(subject_id: subject_id), as: :json
      id = JSON.parse(response.body)["id"]

      get "/Procedure", params: { _id: id, _include: "Procedure:subject" }

      bundle = JSON.parse(response.body)
      included = bundle["entry"].select { |entry| entry.dig("search", "mode") == "include" }
      expect(included.map { |entry| entry["resource"]["resourceType"] }).to eq(["Patient"])
    end
  end

  # 放射線検査の実施記録。1 回の実施を Procedure 1 件(ハブ)で表し、手技が
  # 複数あるときだけ 2 件目以降を partOf でぶら下げる。どちらもオーダーを basedOn に
  # 持つので、カルテのオーダー表示は based-on だけで実施記録を揃えられる。
  describe "based-on / part-of" do
    # オーダー(ServiceRequest)と、それを basedOn に持つ実施記録一式を作る。
    def create_order_with_procedures
      subject_id = create_patient
      post "/ServiceRequest", params: valid_service_request_payload(subject_id: subject_id), as: :json
      order_id = JSON.parse(response.body)["id"]

      post "/Procedure",
           params: valid_procedure_payload(subject_id: subject_id,
                                           basedOn: [{ "reference" => "ServiceRequest/#{order_id}" }]),
           as: :json
      hub_id = JSON.parse(response.body)["id"]

      post "/Procedure",
           params: valid_procedure_payload(subject_id: subject_id,
                                           basedOn: [{ "reference" => "ServiceRequest/#{order_id}" }],
                                           partOf: [{ "reference" => "Procedure/#{hub_id}" }]),
           as: :json
      child_id = JSON.parse(response.body)["id"]

      { subject_id: subject_id, order_id: order_id, hub_id: hub_id, child_id: child_id }
    end

    def match_ids(bundle)
      bundle["entry"].select { |entry| entry.dig("search", "mode") == "match" }
                     .map { |entry| entry["resource"]["id"] }
    end

    it "finds the procedures of an order with based-on" do
      ids = create_order_with_procedures

      get "/Procedure", params: { "based-on" => "ServiceRequest/#{ids[:order_id]}" }

      expect(response).to have_http_status(:ok)
      expect(match_ids(JSON.parse(response.body))).to match_array([ids[:hub_id], ids[:child_id]])
    end

    it "finds only the child procedures with part-of" do
      ids = create_order_with_procedures

      get "/Procedure", params: { "part-of" => "Procedure/#{ids[:hub_id]}" }

      expect(match_ids(JSON.parse(response.body))).to eq([ids[:child_id]])
    end

    it "returns only the hub with part-of:missing=true" do
      ids = create_order_with_procedures

      get "/Procedure", params: { "based-on" => "ServiceRequest/#{ids[:order_id]}", "part-of:missing" => "true" }

      expect(match_ids(JSON.parse(response.body))).to eq([ids[:hub_id]])
    end

    # fhir-client のカルテがオーダー 1 件の実施情報を引く形。実施記録(Procedure)と、
    # それにぶら下がる造影剤(MedicationAdministration)・被曝線量(Observation)まで
    # 1 リクエストで揃うことを固定する。
    it "includes the procedures and their children from the order in one request" do
      ids = create_order_with_procedures

      post "/MedicationAdministration",
           params: valid_medication_administration_payload(
             subject_id: ids[:subject_id],
             partOf: [{ "reference" => "Procedure/#{ids[:hub_id]}" }]
           ),
           as: :json
      contrast_id = JSON.parse(response.body)["id"]

      post "/Observation",
           params: valid_observation_payload(
             subject_id: ids[:subject_id],
             partOf: [{ "reference" => "Procedure/#{ids[:hub_id]}" }]
           ),
           as: :json
      dose_id = JSON.parse(response.body)["id"]

      # :iterate を 2 つ渡すので、Hash では表せない(同じキーの繰り返し)クエリ文字列で投げる。
      get "/ServiceRequest?_id=#{ids[:order_id]}&_revinclude=Procedure:based-on" \
          "&_revinclude:iterate=MedicationAdministration:part-of" \
          "&_revinclude:iterate=Observation:part-of"

      bundle = JSON.parse(response.body)
      included = bundle["entry"].select { |entry| entry.dig("search", "mode") == "include" }
                                .map { |entry| entry["resource"] }
      expect(included.select { |r| r["resourceType"] == "Procedure" }.map { |r| r["id"] })
        .to match_array([ids[:hub_id], ids[:child_id]])
      expect(included.select { |r| r["resourceType"] == "MedicationAdministration" }.map { |r| r["id"] })
        .to eq([contrast_id])
      expect(included.select { |r| r["resourceType"] == "Observation" }.map { |r| r["id"] })
        .to eq([dose_id])
    end
  end
end
