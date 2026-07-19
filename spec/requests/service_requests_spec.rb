require "rails_helper"

RSpec.describe "ServiceRequests", type: :request do
  def create_patient
    post "/Patient", params: valid_patient_payload, as: :json
    JSON.parse(response.body)["id"]
  end

  describe "POST /ServiceRequest" do
    it "creates and returns 201 with Location, ETag, and meta" do
      subject_id = create_patient

      post "/ServiceRequest", params: valid_service_request_payload(subject_id: subject_id), as: :json

      expect(response).to have_http_status(:created)
      expect(response.content_type).to include("application/fhir+json")
      expect(response.headers["Location"]).to match(%r{/ServiceRequest/[\w-]+/_history/1\z})
      expect(response.headers["ETag"]).to eq('W/"1"')

      body = JSON.parse(response.body)
      expect(body["resourceType"]).to eq("ServiceRequest")
      expect(body["meta"]["versionId"]).to eq("1")
    end

    it "does not require identifier" do
      subject_id = create_patient

      post "/ServiceRequest", params: valid_service_request_payload(subject_id: subject_id), as: :json

      expect(response).to have_http_status(:created)
    end

    it "returns 422 when status is missing" do
      subject_id = create_patient

      post "/ServiceRequest", params: valid_service_request_payload(subject_id: subject_id).except("status"), as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "returns 422 for an invalid intent" do
      subject_id = create_patient

      post "/ServiceRequest", params: valid_service_request_payload(subject_id: subject_id, intent: "bogus"), as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "returns 422 when subject references a non-existent patient" do
      post "/ServiceRequest", params: valid_service_request_payload(subject_id: "does-not-exist"), as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "returns 400 when resourceType does not match" do
      subject_id = create_patient

      post "/ServiceRequest", params: valid_service_request_payload(subject_id: subject_id).merge("resourceType" => "Patient"), as: :json

      expect(response).to have_http_status(:bad_request)
    end

    it "returns 400 for malformed JSON" do
      post "/ServiceRequest", params: "{not valid json", headers: { "CONTENT_TYPE" => "application/fhir+json" }

      expect(response).to have_http_status(:bad_request)
    end
  end

  describe "GET /ServiceRequest/:id" do
    it "returns the resource" do
      subject_id = create_patient
      post "/ServiceRequest", params: valid_service_request_payload(subject_id: subject_id), as: :json
      id = JSON.parse(response.body)["id"]

      get "/ServiceRequest/#{id}"

      expect(response).to have_http_status(:ok)
      expect(response.headers["ETag"]).to eq('W/"1"')
    end

    it "returns 404 for an unknown id" do
      get "/ServiceRequest/does-not-exist"

      expect(response).to have_http_status(:not_found)
    end

    it "returns 410 for a deleted resource" do
      subject_id = create_patient
      post "/ServiceRequest", params: valid_service_request_payload(subject_id: subject_id), as: :json
      id = JSON.parse(response.body)["id"]
      delete "/ServiceRequest/#{id}"

      get "/ServiceRequest/#{id}"

      expect(response).to have_http_status(:gone)
    end
  end

  describe "PUT /ServiceRequest/:id" do
    it "updates the resource and increments the version" do
      subject_id = create_patient
      post "/ServiceRequest", params: valid_service_request_payload(subject_id: subject_id), as: :json
      id = JSON.parse(response.body)["id"]

      put "/ServiceRequest/#{id}", params: valid_service_request_payload(subject_id: subject_id, status: "completed"), as: :json

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["status"]).to eq("completed")
      expect(body["meta"]["versionId"]).to eq("2")
    end

    it "returns 412 when If-Match does not match the current version" do
      subject_id = create_patient
      post "/ServiceRequest", params: valid_service_request_payload(subject_id: subject_id), as: :json
      id = JSON.parse(response.body)["id"]

      put "/ServiceRequest/#{id}", params: valid_service_request_payload(subject_id: subject_id),
                                   headers: { "If-Match" => 'W/"99"' }, as: :json

      expect(response).to have_http_status(:precondition_failed)
    end
  end

  describe "DELETE /ServiceRequest/:id" do
    it "deletes the resource and returns 204" do
      subject_id = create_patient
      post "/ServiceRequest", params: valid_service_request_payload(subject_id: subject_id), as: :json
      id = JSON.parse(response.body)["id"]

      delete "/ServiceRequest/#{id}"
      expect(response).to have_http_status(:no_content)

      get "/ServiceRequest/#{id}"
      expect(response).to have_http_status(:gone)
    end
  end

  describe "history and vread" do
    it "returns full version history and a specific version" do
      subject_id = create_patient
      post "/ServiceRequest", params: valid_service_request_payload(subject_id: subject_id), as: :json
      id = JSON.parse(response.body)["id"]
      put "/ServiceRequest/#{id}", params: valid_service_request_payload(subject_id: subject_id, status: "completed"), as: :json

      get "/ServiceRequest/#{id}/_history"
      history = JSON.parse(response.body)
      expect(history["type"]).to eq("history")
      expect(history["total"]).to eq(2)

      get "/ServiceRequest/#{id}/_history/1"
      expect(JSON.parse(response.body)["status"]).to eq("active")
    end
  end

  describe "GET /ServiceRequest (search)" do
    it "finds by subject reference" do
      subject_id = create_patient
      post "/ServiceRequest", params: valid_service_request_payload(subject_id: subject_id), as: :json

      get "/ServiceRequest", params: { subject: "Patient/#{subject_id}" }

      expect(response).to have_http_status(:ok)
      bundle = JSON.parse(response.body)
      expect(bundle["type"]).to eq("searchset")
      expect(bundle["total"]).to eq(1)
    end

    it "finds by status" do
      subject_id = create_patient
      post "/ServiceRequest", params: valid_service_request_payload(subject_id: subject_id, status: "completed"), as: :json

      get "/ServiceRequest", params: { status: "completed" }

      bundle = JSON.parse(response.body)
      expect(bundle["total"]).to be >= 1
    end

    it "excludes deleted resources from search results" do
      subject_id = create_patient
      post "/ServiceRequest", params: valid_service_request_payload(subject_id: subject_id), as: :json
      id = JSON.parse(response.body)["id"]
      delete "/ServiceRequest/#{id}"

      get "/ServiceRequest", params: { _id: id }

      expect(JSON.parse(response.body)["total"]).to eq(0)
    end
  end
end
