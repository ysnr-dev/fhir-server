require "rails_helper"

# _include and _revinclude are the widest opening in a search: they pull in
# resources the caller never matched on. _revinclude in particular runs a fresh
# query against a type the caller did not name, so a shared Practitioner or
# Organization would otherwise act as a handle to every patient hanging off it.
#
# Both patients here are prescribed by the SAME practitioner, which is what
# makes the shared resource a bridge between compartments.
RSpec.describe "patient scope, _include and _revinclude", type: :request do
  around { |example| with_fhir_auth { example.run } }

  let(:system_token) { issue_access_token(scopes: "system/*.*") }
  let(:json_headers) { { "CONTENT_TYPE" => "application/json" } }

  def create_resource(path, payload)
    post path, params: payload.to_json, headers: bearer_header(system_token).merge(json_headers)
    expect(response).to have_http_status(:created), "setup failed for #{path}: #{response.body}"
    JSON.parse(response.body)["id"]
  end

  let!(:mine) { create_resource("/Patient", valid_patient_payload) }
  let!(:theirs) { create_resource("/Patient", valid_patient_payload) }
  let!(:practitioner) { create_resource("/Practitioner", valid_practitioner_payload) }

  let!(:my_request) do
    create_resource("/MedicationRequest", valid_medication_request_payload(
      subject_id: mine, requester: { "reference" => "Practitioner/#{practitioner}" }
    ))
  end
  let!(:their_request) do
    create_resource("/MedicationRequest", valid_medication_request_payload(
      subject_id: theirs, requester: { "reference" => "Practitioner/#{practitioner}" }
    ))
  end

  let(:token) { issue_patient_token(patient_id: mine) }

  def included_ids
    JSON.parse(response.body)["entry"].to_a
        .select { |entry| entry.dig("search", "mode") == "include" }
        .map { |entry| entry["resource"]["id"] }
  end

  describe "_revinclude" do
    # Without the compartment restriction on the reverse query, this returns
    # every patient's MedicationRequest that shares the practitioner.
    it "does not pull in another patient's resources via a shared practitioner" do
      get "/Practitioner?_revinclude=MedicationRequest:requester", headers: bearer_header(token)

      expect(response).to have_http_status(:ok)
      expect(included_ids).to include(my_request)
      expect(included_ids).not_to include(their_request)
    end

    it "does not leak through :iterate either" do
      get "/Practitioner?_revinclude:iterate=MedicationRequest:requester", headers: bearer_header(token)

      expect(response).to have_http_status(:ok)
      expect(included_ids).not_to include(their_request)
    end
  end

  describe "_include" do
    it "resolves a shared practitioner my own resource points at" do
      get "/MedicationRequest?_include=MedicationRequest:requester", headers: bearer_header(token)

      expect(response).to have_http_status(:ok)
      expect(included_ids).to eq([practitioner])
    end

    # The up-front scope check only saw MedicationRequest, so the include must
    # re-check the type it is about to reach for.
    it "omits included types outside the granted scopes" do
      narrow = issue_patient_token(patient_id: mine, scopes: "patient/MedicationRequest.read")

      get "/MedicationRequest?_include=MedicationRequest:requester", headers: bearer_header(narrow)

      expect(response).to have_http_status(:ok)
      expect(included_ids).to be_empty
    end
  end

  describe "_has" do
    # The inner query of a _has runs against a type the caller never named. If
    # it were unrestricted, the presence or absence of a Practitioner in the
    # results would report on another patient's prescriptions.
    it "does not report on another patient's resources" do
      # Delete mine, so the only remaining match for the shared practitioner is
      # the other patient's -- the practitioner must then disappear entirely.
      delete "/MedicationRequest/#{my_request}", headers: bearer_header(system_token)

      get "/Practitioner?_has:MedicationRequest:requester:status=active", headers: bearer_header(token)

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["total"]).to eq(0)
    end

    it "still matches through my own resources" do
      get "/Practitioner?_has:MedicationRequest:requester:status=active", headers: bearer_header(token)

      expect(JSON.parse(response.body)["total"]).to eq(1)
    end
  end

  describe "chained search" do
    it "cannot select through another patient" do
      get "/MedicationRequest?subject.gender=male", headers: bearer_header(token)

      body = JSON.parse(response.body)
      ids = body["entry"].to_a.map { |entry| entry["resource"]["id"] }
      expect(ids).to eq([my_request])
    end
  end
end
