require "rails_helper"

RSpec.describe "Bundles", type: :request do
  describe "POST / (transaction)" do
    it "creates a Patient and a MedicationRequest that references it via urn:uuid" do
      post "/", params: {
        "resourceType" => "Bundle",
        "type" => "transaction",
        "entry" => [
          {
            "fullUrl" => "urn:uuid:p1",
            "resource" => valid_patient_payload,
            "request" => { "method" => "POST", "url" => "Patient" }
          },
          {
            "fullUrl" => "urn:uuid:mr1",
            "resource" => {
              "resourceType" => "MedicationRequest",
              "identifier" => [{ "system" => "http://example.org/mr", "value" => "1" }],
              "status" => "active",
              "intent" => "order",
              "medicationCodeableConcept" => { "text" => "アムロジピン錠5mg" },
              "subject" => { "reference" => "urn:uuid:p1" },
              "authoredOn" => "2026-07-19T10:00:00+09:00"
            },
            "request" => { "method" => "POST", "url" => "MedicationRequest" }
          }
        ]
      }, as: :json

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["resourceType"]).to eq("Bundle")
      expect(body["type"]).to eq("transaction-response")
      expect(body["entry"].size).to eq(2)
      expect(body["entry"][0]["response"]["status"]).to start_with("201")
      expect(body["entry"][1]["response"]["status"]).to start_with("201")

      patient_id = body["entry"][0]["resource"]["id"]
      medication_request = body["entry"][1]["resource"]
      expect(medication_request["subject"]["reference"]).to eq("Patient/#{patient_id}")

      # Persisted correctly, independent of the response body.
      get "/MedicationRequest/#{medication_request['id']}"
      expect(JSON.parse(response.body)["subject"]["reference"]).to eq("Patient/#{patient_id}")
    end

    it "resolves urn:uuid references regardless of entry array order" do
      post "/", params: {
        "resourceType" => "Bundle",
        "type" => "transaction",
        "entry" => [
          {
            # References a fullUrl declared LATER in the array.
            "resource" => {
              "resourceType" => "MedicationRequest",
              "identifier" => [{ "system" => "http://example.org/mr", "value" => "2" }],
              "status" => "active",
              "intent" => "order",
              "medicationCodeableConcept" => { "text" => "Drug" },
              "subject" => { "reference" => "urn:uuid:later-patient" },
              "authoredOn" => "2026-07-19T10:00:00+09:00"
            },
            "request" => { "method" => "POST", "url" => "MedicationRequest" }
          },
          {
            "fullUrl" => "urn:uuid:later-patient",
            "resource" => valid_patient_payload,
            "request" => { "method" => "POST", "url" => "Patient" }
          }
        ]
      }, as: :json

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      patient_id = body["entry"][1]["resource"]["id"]
      expect(body["entry"][0]["resource"]["subject"]["reference"]).to eq("Patient/#{patient_id}")
    end

    it "applies FHIR processing order (DELETE before PUT) regardless of entry array order" do
      post "/Patient", params: valid_patient_payload(gender: "male"), as: :json
      id = JSON.parse(response.body)["id"]

      # Array order is deliberately PUT-then-DELETE, the opposite of FHIR
      # processing order (DELETE, POST, PUT, PATCH, GET).
      post "/", params: {
        "resourceType" => "Bundle",
        "type" => "transaction",
        "entry" => [
          {
            "resource" => valid_patient_payload(gender: "female"),
            "request" => { "method" => "PUT", "url" => "Patient/#{id}" }
          },
          {
            "request" => { "method" => "DELETE", "url" => "Patient/#{id}" }
          }
        ]
      }, as: :json

      expect(response).to have_http_status(:ok)

      # If DELETE actually ran before PUT, the record ends up "undeleted" by
      # the PUT with two version bumps; if array order had been followed
      # instead, it would still be deleted.
      get "/Patient/#{id}"
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["gender"]).to eq("female")
      expect(body["meta"]["versionId"]).to eq("3")
    end

    it "rolls back the entire transaction when any entry fails validation" do
      post "/", params: {
        "resourceType" => "Bundle",
        "type" => "transaction",
        "entry" => [
          {
            "resource" => valid_patient_payload(identifier: [
                                                   { "system" => "urn:oid:1.2.392.100495.20.3.51", "value" => "ROLLBACK-TEST" }
                                                 ]),
            "request" => { "method" => "POST", "url" => "Patient" }
          },
          {
            # Missing required status/intent/subject/authoredOn -> 422
            "resource" => { "resourceType" => "MedicationRequest", "medicationCodeableConcept" => { "text" => "Drug" } },
            "request" => { "method" => "POST", "url" => "MedicationRequest" }
          }
        ]
      }, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      body = JSON.parse(response.body)
      expect(body["resourceType"]).to eq("OperationOutcome")
      expect(body["issue"].first["expression"].first).to eq("Bundle.entry[1]")

      get "/Patient", params: { identifier: "ROLLBACK-TEST" }
      expect(JSON.parse(response.body)["total"]).to eq(0)
    end

    it "returns 422 for an unsupported Bundle.type" do
      post "/", params: { "resourceType" => "Bundle", "type" => "document", "entry" => [] }, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "returns 422 when entry is empty" do
      post "/", params: { "resourceType" => "Bundle", "type" => "transaction", "entry" => [] }, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "POST / (batch)" do
    it "processes entries independently, allowing partial success" do
      post "/", params: {
        "resourceType" => "Bundle",
        "type" => "batch",
        "entry" => [
          {
            "resource" => valid_patient_payload,
            "request" => { "method" => "POST", "url" => "Patient" }
          },
          {
            "request" => { "method" => "GET", "url" => "Patient/does-not-exist" }
          }
        ]
      }, as: :json

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["type"]).to eq("batch-response")
      expect(body["entry"][0]["response"]["status"]).to start_with("201")
      expect(body["entry"][0]["resource"]["resourceType"]).to eq("Patient")
      expect(body["entry"][1]["response"]["status"]).to start_with("404")
      expect(body["entry"][1]["response"]["outcome"]["resourceType"]).to eq("OperationOutcome")

      # The successful entry is NOT rolled back by the other entry's failure.
      created_id = body["entry"][0]["resource"]["id"]
      get "/Patient/#{created_id}"
      expect(response).to have_http_status(:ok)
    end
  end

  describe "entry-point validation" do
    it "returns 400 when resourceType is not Bundle" do
      post "/", params: { "resourceType" => "Patient" }, as: :json

      expect(response).to have_http_status(:bad_request)
    end

    it "returns 400 for malformed JSON" do
      post "/", params: "{not valid json", headers: { "CONTENT_TYPE" => "application/fhir+json" }

      expect(response).to have_http_status(:bad_request)
    end
  end
end
