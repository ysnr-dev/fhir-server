require "rails_helper"

RSpec.describe "Bulk Data $export", type: :request do
  ASYNC = { "Prefer" => "respond-async" }.freeze

  def create_patient(overrides = {}, headers: {})
    post "/Patient", params: valid_patient_payload(overrides), headers: headers, as: :json
    JSON.parse(response.body)["id"]
  end

  # Content-Location only exists on the kick-off's 202 response, so it must be
  # captured immediately -- later `get`/`delete` calls overwrite `response`.
  def status_path_from(kickoff_response)
    kickoff_response.headers["Content-Location"].sub(%r{\Ahttps?://[^/]+}, "")
  end

  def run_export!(headers: ASYNC, path: "/$export", params: {})
    get path, params: params, headers: headers
    expect(response).to have_http_status(:accepted)
    status_path = status_path_from(response)
    perform_enqueued_jobs
    get status_path, headers: headers.except("Prefer")
    expect(response).to have_http_status(:ok)
    JSON.parse(response.body)
  end

  describe "kick-off" do
    it "requires Prefer: respond-async" do
      get "/$export"

      expect(response).to have_http_status(:bad_request)
    end

    it "returns 202 with an absolute Content-Location on GET" do
      get "/$export", headers: ASYNC

      expect(response).to have_http_status(:accepted)
      expect(response.headers["Content-Location"]).to match(%r{/\$export/status/[\w-]+\z})
      expect(response.body).to be_empty
    end

    it "returns 202 for a POST kick-off with a Parameters body" do
      post "/$export", params: { "resourceType" => "Parameters", "parameter" => [] }, headers: ASYNC, as: :json

      expect(response).to have_http_status(:accepted)
      expect(response.headers["Content-Location"]).to be_present
    end

    it "rejects a POST body that isn't a Parameters resource" do
      post "/$export", params: { "resourceType" => "Patient" }, headers: ASYNC, as: :json

      expect(response).to have_http_status(:bad_request)
    end

    it "accepts _outputFormat aliases and rejects unknown ones" do
      get "/$export", params: { "_outputFormat" => "application/ndjson" }, headers: ASYNC
      expect(response).to have_http_status(:accepted)

      get "/$export", params: { "_outputFormat" => "text/csv" }, headers: ASYNC
      expect(response).to have_http_status(:bad_request)
    end

    it "rejects an unknown _type" do
      get "/$export", params: { "_type" => "NoSuchType" }, headers: ASYNC

      expect(response).to have_http_status(:bad_request)
    end

    it "rejects an unsupported parameter unless handling=lenient is requested" do
      get "/$export", params: { "_typeFilter" => "Observation?status=final" }, headers: ASYNC
      expect(response).to have_http_status(:bad_request)

      get "/$export", params: { "_typeFilter" => "Observation?status=final" },
                       headers: ASYNC.merge("Prefer" => "respond-async, handling=lenient")
      expect(response).to have_http_status(:accepted)
    end

    it "returns 429 when a second export is kicked off while one is in progress" do
      get "/$export", headers: ASYNC
      expect(response).to have_http_status(:accepted)

      get "/$export", headers: ASYNC
      expect(response).to have_http_status(:too_many_requests)
      expect(response.headers["Retry-After"]).to be_present
    end
  end

  describe "polling and download" do
    it "returns 202 with X-Progress before the job has run, then the manifest once complete" do
      patient_id = create_patient
      post "/Observation", params: valid_observation_payload(subject_id: patient_id), as: :json

      get "/$export", headers: ASYNC
      status_path = status_path_from(response)

      get status_path
      expect(response).to have_http_status(:accepted)
      expect(response.headers["X-Progress"]).to be_present
      expect(response.headers["Retry-After"]).to be_present

      perform_enqueued_jobs
      get status_path
      expect(response).to have_http_status(:ok)

      manifest = JSON.parse(response.body)
      expect(manifest["transactionTime"]).to be_present
      expect(manifest["request"]).to include("/$export")
      expect(manifest["requiresAccessToken"]).to eq(false)
      output = manifest["output"].find { |o| o["type"] == "Observation" }
      expect(output).to be_present
      expect(output["count"]).to eq(1)
      expect(output["url"]).to match(%r{/\$export/files/[\w-]+\z})
    end

    it "serves NDJSON whose lines parse as versioned FHIR resources" do
      patient_id = create_patient

      manifest = run_export!
      patient_output = manifest["output"].find { |o| o["type"] == "Patient" }

      get patient_output["url"]

      expect(response).to have_http_status(:ok)
      expect(response.content_type).to eq("application/fhir+ndjson")
      lines = response.body.split("\n")
      expect(lines.size).to eq(patient_output["count"])
      resource = JSON.parse(lines.first)
      expect(resource["resourceType"]).to eq("Patient")
      expect(resource["id"]).to eq(patient_id)
      expect(resource.dig("meta", "versionId")).to be_present
    end

    it "cancels an in-progress export; subsequent polls 404" do
      get "/$export", headers: ASYNC
      path = status_path_from(response)

      delete path
      expect(response).to have_http_status(:accepted)

      get path
      expect(response).to have_http_status(:not_found)
    end

    it "404s a poll for an unknown export id" do
      get "/$export/status/no-such-id"

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "Patient/$export" do
    it "includes every patient plus their compartment resources, excluding data with no patient reference" do
      patient_id = create_patient
      post "/Observation", params: valid_observation_payload(subject_id: patient_id), as: :json
      post "/Organization", params: valid_organization_payload, as: :json

      manifest = run_export!(path: "/Patient/$export")

      expect(manifest["output"].map { |o| o["type"] }).to include("Patient", "Observation")
      expect(manifest["output"].map { |o| o["type"] }).not_to include("Organization")
    end

    it "always includes Patient resources even when _type excludes them" do
      create_patient

      manifest = run_export!(path: "/Patient/$export", params: { "_type" => "Observation" })

      expect(manifest["output"].map { |o| o["type"] }).to include("Patient")
    end

    it "honors _since" do
      old_patient_id = create_patient
      Patient.where(id: old_patient_id).update_all(last_updated: 1.day.ago)
      new_patient_id = create_patient

      manifest = run_export!(path: "/Patient/$export", params: { "_since" => 1.hour.ago.iso8601 })
      patient_output = manifest["output"].find { |o| o["type"] == "Patient" }

      get patient_output["url"]
      ids = response.body.split("\n").map { |line| JSON.parse(line)["id"] }

      expect(ids).to include(new_patient_id)
      expect(ids).not_to include(old_patient_id)
    end
  end

  describe "authorization" do
    around { |example| with_fhir_auth { example.run } }

    it "requires a bearer token to kick off an export" do
      get "/$export", headers: ASYNC

      expect(response).to have_http_status(:unauthorized)
    end

    it "requires a wildcard read scope when _type is omitted" do
      token = issue_access_token(scopes: "system/Patient.read")

      get "/$export", headers: ASYNC.merge(bearer_header(token))

      expect(response).to have_http_status(:forbidden)
    end

    it "allows a scoped export limited to the granted _type" do
      token = issue_access_token(scopes: "system/Observation.read")

      get "/$export", params: { "_type" => "Observation" }, headers: ASYNC.merge(bearer_header(token))

      expect(response).to have_http_status(:accepted)
    end

    it "rejects a _type export that exceeds the granted scope" do
      token = issue_access_token(scopes: "system/Observation.read")

      get "/$export", params: { "_type" => "Observation,Condition" }, headers: ASYNC.merge(bearer_header(token))

      expect(response).to have_http_status(:forbidden)
    end

    it "requires Patient read scope for a Patient/$export even when _type omits it" do
      token = issue_access_token(scopes: "system/Observation.read")

      get "/Patient/$export", params: { "_type" => "Observation" }, headers: ASYNC.merge(bearer_header(token))

      expect(response).to have_http_status(:forbidden)
    end

    it "hides another client's export behind a 404 on status and download" do
      owner_token = issue_access_token(scopes: "system/*.*")
      other_token = issue_access_token(scopes: "system/*.*")

      get "/$export", headers: ASYNC.merge(bearer_header(owner_token))
      path = status_path_from(response)

      get path, headers: bearer_header(other_token)
      expect(response).to have_http_status(:not_found)

      delete path, headers: bearer_header(other_token)
      expect(response).to have_http_status(:not_found)
    end

    it "requires the resource type's read scope to download a file" do
      client, = OauthClient.register(name: "spec-client-#{SecureRandom.hex(4)}", scopes: "system/*.*")
      _record, token = AccessToken.issue(client, scopes: %w[system/*.*])
      create_patient(headers: bearer_header(token))

      get "/$export", headers: ASYNC.merge(bearer_header(token))
      status_path = status_path_from(response)
      perform_enqueued_jobs
      get status_path, headers: bearer_header(token)
      manifest = JSON.parse(response.body)
      patient_output = manifest["output"].find { |o| o["type"] == "Patient" }

      # Same client (so the export-ownership check passes) but a narrower
      # second token, isolating the resource-type scope check on download.
      _narrow_record, narrow_token = AccessToken.issue(client, scopes: %w[system/Observation.read])
      get patient_output["url"], headers: bearer_header(narrow_token)

      expect(response).to have_http_status(:forbidden)
    end

    it "advertises requiresAccessToken: true in the manifest" do
      token = issue_access_token(scopes: "system/*.*")
      create_patient(headers: bearer_header(token))

      get "/$export", headers: ASYNC.merge(bearer_header(token))
      status_path = status_path_from(response)
      perform_enqueued_jobs
      get status_path, headers: bearer_header(token)

      expect(JSON.parse(response.body)["requiresAccessToken"]).to eq(true)
    end
  end

  describe "a stale in-progress export" do
    it "is reported as failed instead of leaving pollers waiting forever" do
      get "/$export", headers: ASYNC
      status_path = status_path_from(response)
      BulkExport.update_all(updated_at: 2.hours.ago)

      get status_path

      expect(response).to have_http_status(:internal_server_error)
      expect(JSON.parse(response.body)["issue"].first["diagnostics"]).to include("interrupted")
    end
  end
end
