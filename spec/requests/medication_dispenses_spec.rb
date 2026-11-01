require "rails_helper"

RSpec.describe "MedicationDispenses", type: :request do
  def create_patient
    post "/Patient", params: valid_patient_payload, as: :json
    JSON.parse(response.body)["id"]
  end

  describe "GET /MedicationDispense (part-of)" do
    # 出庫記録(Procedure)に伴う払出(輸血の製剤バッグ)。
    it "finds by part-of and comes back with _revinclude on the procedure search" do
      subject_id = create_patient
      post "/Procedure", params: valid_procedure_payload(subject_id: subject_id), as: :json
      procedure_id = JSON.parse(response.body)["id"]
      post "/MedicationDispense",
           params: valid_medication_dispense_payload(
             subject_id: subject_id, partOf: [{ "reference" => "Procedure/#{procedure_id}" }]
           ),
           as: :json
      # 同じ患者の、出庫記録に紐づかない払出。part-of で拾われないことを確かめる。
      post "/MedicationDispense", params: valid_medication_dispense_payload(subject_id: subject_id), as: :json

      get "/MedicationDispense", params: { "part-of" => "Procedure/#{procedure_id}" }
      expect(JSON.parse(response.body)["total"]).to eq(1)

      get "/Procedure", params: { "_id" => procedure_id, "_revinclude" => "MedicationDispense:part-of" }
      types = JSON.parse(response.body)["entry"].map { |e| e["resource"]["resourceType"] }
      expect(types.sort).to eq(%w[MedicationDispense Procedure])
    end
  end

  describe "POST /MedicationDispense" do
    it "creates and returns 201 with Location, ETag, and meta" do
      subject_id = create_patient

      post "/MedicationDispense", params: valid_medication_dispense_payload(subject_id: subject_id), as: :json

      expect(response).to have_http_status(:created)
      expect(response.content_type).to include("application/fhir+json")
      expect(response.headers["Location"]).to match(%r{/MedicationDispense/[\w-]+/_history/1\z})
      expect(response.headers["ETag"]).to eq('W/"1"')

      body = JSON.parse(response.body)
      expect(body["resourceType"]).to eq("MedicationDispense")
      expect(body["meta"]["profile"]).to eq(["http://jpfhir.jp/fhir/core/StructureDefinition/JP_MedicationDispense"])
    end

    it "returns 422 when status is missing" do
      subject_id = create_patient

      post "/MedicationDispense", params: valid_medication_dispense_payload(subject_id: subject_id).except("status"), as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "returns 422 when medication[x] is missing" do
      subject_id = create_patient

      post "/MedicationDispense",
           params: valid_medication_dispense_payload(subject_id: subject_id).except("medicationCodeableConcept"), as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "returns 422 when subject references a non-existent patient" do
      post "/MedicationDispense", params: valid_medication_dispense_payload(subject_id: "does-not-exist"), as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "returns 400 when resourceType does not match" do
      subject_id = create_patient

      post "/MedicationDispense",
           params: valid_medication_dispense_payload(subject_id: subject_id).merge("resourceType" => "Patient"), as: :json

      expect(response).to have_http_status(:bad_request)
    end
  end

  describe "GET /MedicationDispense/:id" do
    it "returns the resource" do
      subject_id = create_patient
      post "/MedicationDispense", params: valid_medication_dispense_payload(subject_id: subject_id), as: :json
      id = JSON.parse(response.body)["id"]

      get "/MedicationDispense/#{id}"

      expect(response).to have_http_status(:ok)
    end

    it "returns 404 for an unknown id" do
      get "/MedicationDispense/does-not-exist"

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "PUT and DELETE" do
    it "updates and then deletes" do
      subject_id = create_patient
      post "/MedicationDispense", params: valid_medication_dispense_payload(subject_id: subject_id), as: :json
      id = JSON.parse(response.body)["id"]

      put "/MedicationDispense/#{id}",
          params: valid_medication_dispense_payload(subject_id: subject_id, status: "in-progress"), as: :json
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["meta"]["versionId"]).to eq("2")

      delete "/MedicationDispense/#{id}"
      expect(response).to have_http_status(:no_content)

      get "/MedicationDispense/#{id}"
      expect(response).to have_http_status(:gone)
    end
  end

  describe "GET /MedicationDispense (search)" do
    it "finds by subject reference" do
      subject_id = create_patient
      post "/MedicationDispense", params: valid_medication_dispense_payload(subject_id: subject_id), as: :json

      get "/MedicationDispense", params: { subject: "Patient/#{subject_id}" }

      bundle = JSON.parse(response.body)
      expect(bundle["type"]).to eq("searchset")
      expect(bundle["total"]).to eq(1)
    end

    it "finds by medication code" do
      subject_id = create_patient
      post "/MedicationDispense", params: valid_medication_dispense_payload(subject_id: subject_id), as: :json

      get "/MedicationDispense", params: { code: "620004422" }

      expect(JSON.parse(response.body)["total"]).to be >= 1
    end

    describe "_include" do
      it "includes the referenced Patient via MedicationDispense:subject" do
        subject_id = create_patient
        post "/MedicationDispense", params: valid_medication_dispense_payload(subject_id: subject_id), as: :json
        id = JSON.parse(response.body)["id"]

        get "/MedicationDispense", params: { _id: id, _include: "MedicationDispense:subject" }

        bundle = JSON.parse(response.body)
        included = bundle["entry"].select { |entry| entry.dig("search", "mode") == "include" }
        expect(included.map { |entry| entry["resource"]["resourceType"] }).to eq(["Patient"])
        expect(included.first["resource"]["id"]).to eq(subject_id)
      end

      it "includes the referenced MedicationRequest via MedicationDispense:prescription" do
        subject_id = create_patient
        post "/MedicationRequest", params: valid_medication_request_payload(subject_id: subject_id), as: :json
        request_id = JSON.parse(response.body)["id"]
        post "/MedicationDispense",
             params: valid_medication_dispense_payload(
               subject_id: subject_id,
               authorizingPrescription: [{ "reference" => "MedicationRequest/#{request_id}" }]
             ),
             as: :json
        id = JSON.parse(response.body)["id"]

        get "/MedicationDispense", params: { _id: id, _include: "MedicationDispense:prescription" }

        bundle = JSON.parse(response.body)
        included = bundle["entry"].select { |entry| entry.dig("search", "mode") == "include" }
        expect(included.map { |entry| entry["resource"]["resourceType"] }).to eq(["MedicationRequest"])
        expect(included.first["resource"]["id"]).to eq(request_id)
      end
    end

    it "finds by prescription (authorizingPrescription containment)" do
      subject_id = create_patient
      post "/MedicationRequest", params: valid_medication_request_payload(subject_id: subject_id), as: :json
      request_id = JSON.parse(response.body)["id"]
      post "/MedicationDispense",
           params: valid_medication_dispense_payload(
             subject_id: subject_id,
             authorizingPrescription: [{ "reference" => "MedicationRequest/#{request_id}" }]
           ),
           as: :json

      get "/MedicationDispense", params: { prescription: "MedicationRequest/#{request_id}" }

      expect(JSON.parse(response.body)["total"]).to eq(1)
    end
  end
end
