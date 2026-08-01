require "rails_helper"

# The security boundary of the interactive launch: a patient-context token must
# see its own compartment and nothing else, through every route that reads data
# -- direct reads, search, chained search, _include/_revinclude, $everything and
# Bundle entries alike.
#
# Out-of-compartment resources are 404, never 403: a 403 would confirm the
# resource exists, and existence is itself patient information.
RSpec.describe "patient scope access", type: :request do
  around { |example| with_fhir_auth { example.run } }

  # Two patients with parallel data, so every assertion below has a matching
  # negative case that differs only in whose record it is.
  let(:system_token) { issue_access_token(scopes: "system/*.*") }
  let(:json_headers) { { "CONTENT_TYPE" => "application/json" } }

  def create_resource(path, payload)
    post path, params: payload.to_json, headers: bearer_header(system_token).merge(json_headers)
    expect(response).to have_http_status(:created), "setup failed for #{path}: #{response.body}"
    JSON.parse(response.body)["id"]
  end

  let!(:mine) { create_resource("/Patient", valid_patient_payload) }
  let!(:theirs) { create_resource("/Patient", valid_patient_payload) }
  let!(:my_observation) { create_resource("/Observation", valid_observation_payload(subject_id: mine)) }
  let!(:their_observation) { create_resource("/Observation", valid_observation_payload(subject_id: theirs)) }

  let(:token) { issue_patient_token(patient_id: mine) }

  describe "instance read" do
    it "returns my own resources" do
      get "/Observation/#{my_observation}", headers: bearer_header(token)

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["id"]).to eq(my_observation)
    end

    it "returns my own Patient record" do
      get "/Patient/#{mine}", headers: bearer_header(token)

      expect(response).to have_http_status(:ok)
    end

    it "hides another patient's resource behind a 404" do
      get "/Observation/#{their_observation}", headers: bearer_header(token)

      expect(response).to have_http_status(:not_found)
    end

    it "hides another Patient record behind a 404" do
      get "/Patient/#{theirs}", headers: bearer_header(token)

      expect(response).to have_http_status(:not_found)
    end

    # 410 would confirm the resource once existed, which is the same disclosure
    # a 200 would make.
    it "reports another patient's deleted resource as 404, not 410" do
      delete "/Observation/#{their_observation}", headers: bearer_header(system_token)
      expect(response).to have_http_status(:no_content)

      get "/Observation/#{their_observation}", headers: bearer_header(token)
      expect(response).to have_http_status(:not_found)
    end

    it "still reports my own deleted resource as 410" do
      delete "/Observation/#{my_observation}", headers: bearer_header(system_token)

      get "/Observation/#{my_observation}", headers: bearer_header(token)
      expect(response).to have_http_status(:gone)
    end
  end

  describe "search" do
    it "returns only my resources" do
      get "/Observation", headers: bearer_header(token)

      body = JSON.parse(response.body)
      ids = body["entry"].to_a.map { |entry| entry["resource"]["id"] }
      expect(ids).to eq([my_observation])
      expect(body["total"]).to eq(1)
    end

    it "returns nothing when filtering explicitly for another patient's resource" do
      get "/Observation?_id=#{their_observation}", headers: bearer_header(token)

      expect(JSON.parse(response.body)["total"]).to eq(0)
    end

    it "returns only me from a Patient search" do
      get "/Patient", headers: bearer_header(token)

      body = JSON.parse(response.body)
      expect(body["total"]).to eq(1)
      expect(body["entry"].first["resource"]["id"]).to eq(mine)
    end

    it "returns nothing for a chained search naming another patient" do
      get "/Observation?subject=Patient/#{theirs}", headers: bearer_header(token)

      expect(JSON.parse(response.body)["total"]).to eq(0)
    end
  end

  describe "history" do
    it "allows instance history for my own resource" do
      get "/Observation/#{my_observation}/_history", headers: bearer_header(token)

      expect(response).to have_http_status(:ok)
    end

    it "404s instance history for another patient's resource" do
      get "/Observation/#{their_observation}/_history", headers: bearer_header(token)

      expect(response).to have_http_status(:not_found)
    end

    it "404s vread for another patient's resource" do
      get "/Observation/#{their_observation}/_history/1", headers: bearer_header(token)

      expect(response).to have_http_status(:not_found)
    end
  end

  # These reach past any single compartment by construction, so there is no
  # filtered form of them to grant -- they are system-scope only.
  describe "interactions that span every compartment" do
    it "denies server-wide history" do
      get "/_history", headers: bearer_header(token)

      expect(response).to have_http_status(:forbidden)
    end

    it "denies type-level history" do
      get "/Observation/_history", headers: bearer_header(token)

      expect(response).to have_http_status(:forbidden)
    end

    it "denies the audit trail" do
      get "/AuditEvent", headers: bearer_header(token)

      expect(response).to have_http_status(:forbidden)
    end

    it "denies kicking off a bulk export" do
      get "/Patient/$export", headers: bearer_header(token).merge("Prefer" => "respond-async")

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "$everything" do
    it "returns my own compartment" do
      get "/Patient/#{mine}/$everything", headers: bearer_header(token)

      expect(response).to have_http_status(:ok)
      ids = JSON.parse(response.body)["entry"].map { |entry| entry["resource"]["id"] }
      expect(ids).to include(mine, my_observation)
      expect(ids).not_to include(theirs, their_observation)
    end

    it "404s another patient's compartment" do
      get "/Patient/#{theirs}/$everything", headers: bearer_header(token)

      expect(response).to have_http_status(:not_found)
    end

    # The up-front scope check only sees Patient, so without a type filter the
    # sweep would return types the user never consented to.
    it "omits types outside the granted scopes" do
      narrow = issue_patient_token(patient_id: mine, scopes: "patient/Patient.read")

      get "/Patient/#{mine}/$everything", headers: bearer_header(narrow)

      expect(response).to have_http_status(:ok)
      ids = JSON.parse(response.body)["entry"].map { |entry| entry["resource"]["id"] }
      expect(ids).to eq([mine])
    end
  end

  # Shared terminology and directory data has no patient compartment, and a
  # patient's own records are unreadable without it.
  describe "types with no patient compartment" do
    let!(:medication) { create_resource("/Medication", valid_medication_payload) }

    it "allows reading shared reference data" do
      get "/Medication/#{medication}", headers: bearer_header(token)
      expect(response).to have_http_status(:ok)

      get "/Medication", headers: bearer_header(token)
      expect(JSON.parse(response.body)["total"]).to eq(1)
    end

    # Binary equally has no Patient reference, but it holds document payloads.
    # Treating it as shared data would expose every patient's attachments, so
    # it fails closed until it can be authorised via its DocumentReference.
    describe "Binary" do
      let!(:binary) { create_resource("/Binary", valid_binary_payload) }

      it "is not readable by id" do
        get "/Binary/#{binary}", headers: bearer_header(token)

        expect(response).to have_http_status(:not_found)
      end

      it "is not returned by search" do
        get "/Binary", headers: bearer_header(token)

        expect(JSON.parse(response.body)["total"]).to eq(0)
      end

      it "stays readable with a system token" do
        get "/Binary/#{binary}", headers: bearer_header(system_token)

        expect(response).to have_http_status(:ok)
      end
    end

    # Group.member is 0..*, so Group has no compartment either. It fails closed
    # for the same reason as Binary: its member roster would disclose which
    # other patients are in the cohort, and a cohort name is a clinical fact.
    describe "Group" do
      let!(:group) { create_resource("/Group", valid_group_payload(member_ids: [mine])) }

      it "is not readable by id" do
        get "/Group/#{group}", headers: bearer_header(token)

        expect(response).to have_http_status(:not_found)
      end

      it "is not returned by search even when the patient is a member" do
        get "/Group", headers: bearer_header(token)

        expect(JSON.parse(response.body)["total"]).to eq(0)
      end

      it "stays readable with a system token" do
        get "/Group/#{group}", headers: bearer_header(system_token)

        expect(response).to have_http_status(:ok)
      end
    end
  end

  describe "writes" do
    it "denies creating a resource" do
      post "/Observation", params: valid_observation_payload(subject_id: mine).to_json,
                           headers: bearer_header(token).merge(json_headers)

      expect(response).to have_http_status(:forbidden)
      # The message must name a scope the caller could actually obtain.
      expect(JSON.parse(response.body)["issue"].first["diagnostics"]).to include("patient/Observation.write")
    end

    it "denies deleting my own resource" do
      delete "/Observation/#{my_observation}", headers: bearer_header(token)

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "Bundle entries" do
    def batch(entries)
      post "/", params: { "resourceType" => "Bundle", "type" => "batch", "entry" => entries }.to_json,
                headers: bearer_header(token).merge(json_headers)
    end

    it "applies the compartment to a GET read entry" do
      batch([
        { "request" => { "method" => "GET", "url" => "Observation/#{my_observation}" } },
        { "request" => { "method" => "GET", "url" => "Observation/#{their_observation}" } }
      ])

      statuses = JSON.parse(response.body)["entry"].map { |entry| entry["response"]["status"] }
      expect(statuses).to eq(["200 OK", "404 Not Found"])
    end

    it "applies the compartment to a GET search entry" do
      batch([{ "request" => { "method" => "GET", "url" => "Observation" } }])

      bundle = JSON.parse(response.body)["entry"].first["resource"]
      expect(bundle["total"]).to eq(1)
      expect(bundle["entry"].first["resource"]["id"]).to eq(my_observation)
    end

    it "rejects the whole bundle when it contains a write entry" do
      batch([
        { "request" => { "method" => "GET", "url" => "Observation/#{my_observation}" } },
        { "request" => { "method" => "POST", "url" => "Observation" },
          "resource" => valid_observation_payload(subject_id: mine) }
      ])

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "conditional read" do
    it "honours If-None-Match on my own resource" do
      get "/Observation/#{my_observation}", headers: bearer_header(token)
      etag = response.headers["ETag"]

      get "/Observation/#{my_observation}", headers: bearer_header(token).merge("If-None-Match" => etag)
      expect(response).to have_http_status(:not_modified)
    end

    it "404s another patient's resource regardless of If-None-Match" do
      get "/Observation/#{their_observation}", headers: bearer_header(token).merge("If-None-Match" => 'W/"1"')

      expect(response).to have_http_status(:not_found)
    end
  end

  # A patient/ scope means nothing without a launch context to filter against.
  # Honouring it on a context-free token would grant unrestricted reads.
  describe "a patient scope on a token with no launch context" do
    it "grants nothing" do
      client, = OauthClient.register(
        name: "mis-registered", scopes: "patient/*.read",
        redirect_uris: "https://app.example/cb", client_type: "public"
      )
      _record, raw = AccessToken.issue(client, scopes: ["patient/*.read"])

      get "/Observation", headers: bearer_header(raw)

      expect(response).to have_http_status(:forbidden)
    end
  end
end
