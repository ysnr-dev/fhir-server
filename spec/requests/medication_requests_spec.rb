require "rails_helper"

RSpec.describe "MedicationRequests", type: :request do
  def create_patient
    post "/Patient", params: valid_patient_payload, as: :json
    JSON.parse(response.body)["id"]
  end

  describe "POST /MedicationRequest" do
    it "creates and returns 201 with Location, ETag, and meta" do
      subject_id = create_patient

      post "/MedicationRequest", params: valid_medication_request_payload(subject_id: subject_id), as: :json

      expect(response).to have_http_status(:created)
      expect(response.content_type).to include("application/fhir+json")
      expect(response.headers["Location"]).to match(%r{/MedicationRequest/[\w-]+/_history/1\z})
      expect(response.headers["ETag"]).to eq('W/"1"')

      body = JSON.parse(response.body)
      expect(body["resourceType"]).to eq("MedicationRequest")
      expect(body["meta"]["versionId"]).to eq("1")
    end

    it "returns 422 when status is missing" do
      subject_id = create_patient

      post "/MedicationRequest", params: valid_medication_request_payload(subject_id: subject_id).except("status"), as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "returns 422 for an invalid status" do
      subject_id = create_patient

      post "/MedicationRequest", params: valid_medication_request_payload(subject_id: subject_id, status: "bogus"), as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "returns 422 when intent is missing" do
      subject_id = create_patient

      post "/MedicationRequest", params: valid_medication_request_payload(subject_id: subject_id).except("intent"), as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "returns 422 when medicationCodeableConcept is missing" do
      subject_id = create_patient

      post "/MedicationRequest", params: valid_medication_request_payload(subject_id: subject_id).except("medicationCodeableConcept"), as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "returns 422 when medicationReference is used instead of medicationCodeableConcept" do
      subject_id = create_patient
      payload = valid_medication_request_payload(subject_id: subject_id).except("medicationCodeableConcept")
      payload["medicationReference"] = { "reference" => "Medication/123" }

      post "/MedicationRequest", params: payload, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "returns 422 when subject references a non-existent patient" do
      post "/MedicationRequest", params: valid_medication_request_payload(subject_id: "does-not-exist"), as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "returns 422 when authoredOn is missing" do
      subject_id = create_patient

      post "/MedicationRequest", params: valid_medication_request_payload(subject_id: subject_id).except("authoredOn"), as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "returns 400 when resourceType does not match" do
      subject_id = create_patient

      post "/MedicationRequest", params: valid_medication_request_payload(subject_id: subject_id).merge("resourceType" => "Patient"), as: :json

      expect(response).to have_http_status(:bad_request)
    end

    it "returns 400 for malformed JSON" do
      post "/MedicationRequest", params: "{not valid json", headers: { "CONTENT_TYPE" => "application/fhir+json" }

      expect(response).to have_http_status(:bad_request)
    end
  end

  describe "GET /MedicationRequest/:id" do
    it "returns the resource" do
      subject_id = create_patient
      post "/MedicationRequest", params: valid_medication_request_payload(subject_id: subject_id), as: :json
      id = JSON.parse(response.body)["id"]

      get "/MedicationRequest/#{id}"

      expect(response).to have_http_status(:ok)
      expect(response.headers["ETag"]).to eq('W/"1"')
    end

    it "returns 404 for an unknown id" do
      get "/MedicationRequest/does-not-exist"

      expect(response).to have_http_status(:not_found)
    end

    it "returns 410 for a deleted resource" do
      subject_id = create_patient
      post "/MedicationRequest", params: valid_medication_request_payload(subject_id: subject_id), as: :json
      id = JSON.parse(response.body)["id"]
      delete "/MedicationRequest/#{id}"

      get "/MedicationRequest/#{id}"

      expect(response).to have_http_status(:gone)
    end
  end

  describe "PUT /MedicationRequest/:id" do
    it "updates the resource and increments the version" do
      subject_id = create_patient
      post "/MedicationRequest", params: valid_medication_request_payload(subject_id: subject_id), as: :json
      id = JSON.parse(response.body)["id"]

      put "/MedicationRequest/#{id}", params: valid_medication_request_payload(subject_id: subject_id, status: "completed"), as: :json

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["status"]).to eq("completed")
      expect(body["meta"]["versionId"]).to eq("2")
      expect(response.headers["ETag"]).to eq('W/"2"')
    end

    it "returns 412 when If-Match does not match the current version" do
      subject_id = create_patient
      post "/MedicationRequest", params: valid_medication_request_payload(subject_id: subject_id), as: :json
      id = JSON.parse(response.body)["id"]

      put "/MedicationRequest/#{id}", params: valid_medication_request_payload(subject_id: subject_id),
                                       headers: { "If-Match" => 'W/"99"' }, as: :json

      expect(response).to have_http_status(:precondition_failed)
    end

    it "returns 404 for an unknown id" do
      subject_id = create_patient

      put "/MedicationRequest/does-not-exist", params: valid_medication_request_payload(subject_id: subject_id), as: :json

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "DELETE /MedicationRequest/:id" do
    it "deletes the resource and returns 204" do
      subject_id = create_patient
      post "/MedicationRequest", params: valid_medication_request_payload(subject_id: subject_id), as: :json
      id = JSON.parse(response.body)["id"]

      delete "/MedicationRequest/#{id}"
      expect(response).to have_http_status(:no_content)

      get "/MedicationRequest/#{id}"
      expect(response).to have_http_status(:gone)
    end

    it "is idempotent when deleting an already-deleted resource" do
      subject_id = create_patient
      post "/MedicationRequest", params: valid_medication_request_payload(subject_id: subject_id), as: :json
      id = JSON.parse(response.body)["id"]

      delete "/MedicationRequest/#{id}"
      delete "/MedicationRequest/#{id}"

      expect(response).to have_http_status(:no_content)
    end
  end

  describe "history and vread" do
    it "returns full version history as a history Bundle" do
      subject_id = create_patient
      post "/MedicationRequest", params: valid_medication_request_payload(subject_id: subject_id), as: :json
      id = JSON.parse(response.body)["id"]
      put "/MedicationRequest/#{id}", params: valid_medication_request_payload(subject_id: subject_id, status: "completed"), as: :json

      get "/MedicationRequest/#{id}/_history"

      expect(response).to have_http_status(:ok)
      history = JSON.parse(response.body)
      expect(history["resourceType"]).to eq("Bundle")
      expect(history["type"]).to eq("history")
      expect(history["total"]).to eq(2)
    end

    it "returns a specific prior version via vread" do
      subject_id = create_patient
      post "/MedicationRequest", params: valid_medication_request_payload(subject_id: subject_id), as: :json
      id = JSON.parse(response.body)["id"]
      put "/MedicationRequest/#{id}", params: valid_medication_request_payload(subject_id: subject_id, status: "completed"), as: :json

      get "/MedicationRequest/#{id}/_history/1"

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["status"]).to eq("active")
    end
  end

  describe "GET /MedicationRequest (search)" do
    it "finds by subject reference" do
      subject_id = create_patient
      post "/MedicationRequest", params: valid_medication_request_payload(subject_id: subject_id), as: :json

      get "/MedicationRequest", params: { subject: "Patient/#{subject_id}" }

      expect(response).to have_http_status(:ok)
      bundle = JSON.parse(response.body)
      expect(bundle["resourceType"]).to eq("Bundle")
      expect(bundle["type"]).to eq("searchset")
      expect(bundle["total"]).to eq(1)
    end

    it "finds by status" do
      subject_id = create_patient
      post "/MedicationRequest", params: valid_medication_request_payload(subject_id: subject_id, status: "completed"), as: :json

      get "/MedicationRequest", params: { status: "completed" }

      bundle = JSON.parse(response.body)
      expect(bundle["total"]).to be >= 1
    end

    it "finds by medication code" do
      subject_id = create_patient
      post "/MedicationRequest", params: valid_medication_request_payload(subject_id: subject_id), as: :json

      get "/MedicationRequest", params: { code: "620004422" }

      bundle = JSON.parse(response.body)
      expect(bundle["total"]).to be >= 1
    end

    it "excludes deleted resources from search results" do
      subject_id = create_patient
      post "/MedicationRequest", params: valid_medication_request_payload(subject_id: subject_id), as: :json
      id = JSON.parse(response.body)["id"]
      delete "/MedicationRequest/#{id}"

      get "/MedicationRequest", params: { _id: id }

      expect(JSON.parse(response.body)["total"]).to eq(0)
    end
  end
end
