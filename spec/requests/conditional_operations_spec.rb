require "rails_helper"

RSpec.describe "Conditional operations", type: :request do
  MRN_SYSTEM = "urn:oid:1.2.392.100495.20.3.51".freeze

  def conditional_put_url(mrn)
    "/Patient?identifier=#{Rack::Utils.escape("#{MRN_SYSTEM}|#{mrn}")}"
  end

  def patient_payload(mrn)
    valid_patient_payload("identifier" => [{ "system" => MRN_SYSTEM, "value" => mrn }])
  end

  describe "conditional create (POST + If-None-Exist)" do
    it "creates with 201 when nothing matches" do
      post "/Patient", params: patient_payload("cc-1"), as: :json,
                       headers: { "If-None-Exist" => "identifier=#{MRN_SYSTEM}|cc-1" }

      expect(response).to have_http_status(:created)
      expect(Patient.where(deleted: false).count).to eq(1)
    end

    it "returns 200 with the existing resource when one matches, without creating a duplicate" do
      post "/Patient", params: patient_payload("cc-2"), as: :json
      existing_id = JSON.parse(response.body)["id"]

      post "/Patient", params: patient_payload("cc-2"), as: :json,
                       headers: { "If-None-Exist" => "identifier=#{MRN_SYSTEM}|cc-2" }

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["id"]).to eq(existing_id)
      expect(Patient.where(deleted: false).count).to eq(1)
    end

    it "returns 412 when multiple resources match" do
      post "/Patient", params: patient_payload("cc-3"), as: :json
      post "/Patient", params: patient_payload("cc-3"), as: :json

      post "/Patient", params: patient_payload("cc-3"), as: :json,
                       headers: { "If-None-Exist" => "identifier=#{MRN_SYSTEM}|cc-3" }

      expect(response).to have_http_status(:precondition_failed)
      expect(Patient.where(deleted: false).count).to eq(2)
    end

    it "returns 400 for unrecognized criteria" do
      post "/Patient", params: patient_payload("cc-4"), as: :json,
                       headers: { "If-None-Exist" => "bogus-param=1" }

      expect(response).to have_http_status(:bad_request)
      expect(Patient.count).to eq(0)
    end
  end

  describe "conditional update (PUT /Patient?criteria)" do
    it "creates with 201 when nothing matches" do
      put conditional_put_url("cu-1"), params: patient_payload("cu-1"), as: :json

      expect(response).to have_http_status(:created)
      expect(JSON.parse(response.body)["meta"]["versionId"]).to eq("1")
    end

    it "updates the matched resource with 200 when one matches" do
      post "/Patient", params: patient_payload("cu-2"), as: :json
      existing_id = JSON.parse(response.body)["id"]

      put conditional_put_url("cu-2"),
          params: patient_payload("cu-2").merge("gender" => "female"), as: :json

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["id"]).to eq(existing_id)
      expect(body["meta"]["versionId"]).to eq("2")
      expect(body["gender"]).to eq("female")
    end

    it "is idempotent as a create-or-update upsert" do
      put conditional_put_url("cu-3"), params: patient_payload("cu-3"), as: :json
      expect(response).to have_http_status(:created)

      put conditional_put_url("cu-3"), params: patient_payload("cu-3"), as: :json
      expect(response).to have_http_status(:ok)
      expect(Patient.where(deleted: false).count).to eq(1)
    end

    it "returns 412 when multiple resources match" do
      post "/Patient", params: patient_payload("cu-4"), as: :json
      post "/Patient", params: patient_payload("cu-4"), as: :json

      put conditional_put_url("cu-4"), params: patient_payload("cu-4"), as: :json

      expect(response).to have_http_status(:precondition_failed)
    end

    it "returns 400 when the payload id contradicts the matched resource" do
      post "/Patient", params: patient_payload("cu-5"), as: :json

      put conditional_put_url("cu-5"),
          params: patient_payload("cu-5").merge("id" => "some-other-id"), as: :json

      expect(response).to have_http_status(:bad_request)
    end

    it "returns 400 when the criteria are empty" do
      put "/Patient", params: patient_payload("cu-6"), as: :json

      expect(response).to have_http_status(:bad_request)
    end
  end

  describe "conditional delete (DELETE /Patient?criteria)" do
    it "deletes the single matching resource with 204" do
      post "/Patient", params: patient_payload("cd-1"), as: :json
      patient_id = JSON.parse(response.body)["id"]

      delete conditional_put_url("cd-1")

      expect(response).to have_http_status(:no_content)
      expect(Patient.find(patient_id).deleted).to be(true)
      expect(ResourceVersion.where(resource_id: patient_id, deleted: true).count).to eq(1)

      get "/Patient/#{patient_id}"
      expect(response).to have_http_status(:gone)
    end

    it "returns 204 when nothing matches, and is idempotent" do
      delete conditional_put_url("cd-2")
      expect(response).to have_http_status(:no_content)

      post "/Patient", params: patient_payload("cd-2"), as: :json
      delete conditional_put_url("cd-2")
      expect(response).to have_http_status(:no_content)

      # The deleted resource no longer matches, so a repeat is still 204.
      delete conditional_put_url("cd-2")
      expect(response).to have_http_status(:no_content)
    end

    it "returns 412 when multiple resources match, deleting nothing" do
      post "/Patient", params: patient_payload("cd-3"), as: :json
      post "/Patient", params: patient_payload("cd-3"), as: :json

      delete conditional_put_url("cd-3")

      expect(response).to have_http_status(:precondition_failed)
      expect(Patient.where(deleted: false).count).to eq(2)
    end

    it "returns 400 for unrecognized or empty criteria" do
      delete "/Patient?bogus-param=1"
      expect(response).to have_http_status(:bad_request)

      delete "/Patient"
      expect(response).to have_http_status(:bad_request)
    end
  end

  describe "Bundle transaction with conditional delete entries" do
    it "deletes via DELETE with search criteria in the entry url" do
      post "/Patient", params: patient_payload("bd-1"), as: :json
      patient_id = JSON.parse(response.body)["id"]

      bundle = {
        "resourceType" => "Bundle",
        "type" => "transaction",
        "entry" => [
          { "request" => { "method" => "DELETE", "url" => "Patient?identifier=#{MRN_SYSTEM}|bd-1" } }
        ]
      }

      post "/", params: bundle, as: :json

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["entry"][0]["response"]["status"]).to start_with("204")
      expect(Patient.find(patient_id).deleted).to be(true)
    end
  end

  describe "Bundle transaction with ifNoneExist" do
    def transaction_bundle(mrn)
      {
        "resourceType" => "Bundle",
        "type" => "transaction",
        "entry" => [
          {
            "fullUrl" => "urn:uuid:11111111-1111-1111-1111-111111111111",
            "resource" => patient_payload(mrn),
            "request" => { "method" => "POST", "url" => "Patient", "ifNoneExist" => "identifier=#{MRN_SYSTEM}|#{mrn}" }
          },
          {
            "resource" => valid_observation_payload(subject_id: "placeholder")
              .merge("subject" => { "reference" => "urn:uuid:11111111-1111-1111-1111-111111111111" }),
            "request" => { "method" => "POST", "url" => "Observation" }
          }
        ]
      }
    end

    it "creates the patient on first submission and reuses it on resubmission" do
      post "/", params: transaction_bundle("tx-1"), as: :json
      expect(response).to have_http_status(:ok)
      first = JSON.parse(response.body)
      expect(first["entry"][0]["response"]["status"]).to start_with("201")

      post "/", params: transaction_bundle("tx-1"), as: :json
      expect(response).to have_http_status(:ok)
      second = JSON.parse(response.body)
      expect(second["entry"][0]["response"]["status"]).to start_with("200")

      expect(Patient.where(deleted: false).count).to eq(1)
      expect(Observation.where(deleted: false).count).to eq(2)

      # Both observations point at the same (deduplicated) patient.
      subjects = Observation.order(:created_at).pluck(:subject_reference).uniq
      expect(subjects.size).to eq(1)
    end
  end

  describe "Bundle transaction with conditional references" do
    it "resolves a conditional reference to the existing resource" do
      post "/Patient", params: patient_payload("ref-1"), as: :json
      patient_id = JSON.parse(response.body)["id"]

      bundle = {
        "resourceType" => "Bundle",
        "type" => "transaction",
        "entry" => [
          {
            "resource" => valid_observation_payload(subject_id: "placeholder")
              .merge("subject" => { "reference" => "Patient?identifier=#{MRN_SYSTEM}|ref-1" }),
            "request" => { "method" => "POST", "url" => "Observation" }
          }
        ]
      }

      post "/", params: bundle, as: :json

      expect(response).to have_http_status(:ok)
      observation = Observation.first
      expect(observation.subject_reference).to eq("Patient/#{patient_id}")
      expect(observation.content.dig("subject", "reference")).to eq("Patient/#{patient_id}")
    end

    it "fails the whole transaction when a conditional reference matches nothing" do
      bundle = {
        "resourceType" => "Bundle",
        "type" => "transaction",
        "entry" => [
          {
            "resource" => valid_observation_payload(subject_id: "placeholder")
              .merge("subject" => { "reference" => "Patient?identifier=#{MRN_SYSTEM}|no-such-mrn" }),
            "request" => { "method" => "POST", "url" => "Observation" }
          }
        ]
      }

      post "/", params: bundle, as: :json

      expect(response).to have_http_status(:precondition_failed)
      expect(Observation.count).to eq(0)
    end
  end

  describe "Bundle transaction with conditional update entries" do
    it "upserts via PUT with search criteria in the entry url" do
      bundle = {
        "resourceType" => "Bundle",
        "type" => "transaction",
        "entry" => [
          {
            "resource" => patient_payload("bu-1"),
            "request" => { "method" => "PUT", "url" => "Patient?identifier=#{MRN_SYSTEM}|bu-1" }
          }
        ]
      }

      post "/", params: bundle, as: :json
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["entry"][0]["response"]["status"]).to start_with("201")

      post "/", params: bundle, as: :json
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["entry"][0]["response"]["status"]).to start_with("200")

      expect(Patient.where(deleted: false).count).to eq(1)
    end
  end
end
