require "rails_helper"

RSpec.describe "Type- and system-level history", type: :request do
  def create_patient(overrides = {})
    post "/Patient", params: valid_patient_payload(overrides), as: :json
    JSON.parse(response.body)["id"]
  end

  describe "GET /{type}/_history" do
    it "returns every version of every resource of the type, newest first" do
      first_id = create_patient
      second_id = create_patient
      put "/Patient/#{second_id}", params: valid_patient_payload("gender" => "female"), as: :json
      delete "/Patient/#{first_id}"

      get "/Patient/_history"

      expect(response).to have_http_status(:ok)
      expect(response.content_type).to start_with("application/fhir+json")
      body = JSON.parse(response.body)
      expect(body["resourceType"]).to eq("Bundle")
      expect(body["type"]).to eq("history")
      expect(body["total"]).to eq(4)

      methods = body["entry"].map { |e| e.dig("request", "method") }
      expect(methods).to eq(%w[DELETE PUT POST POST])

      timestamps = body["entry"].map { |e| e.dig("response", "lastModified") }
      expect(timestamps).to eq(timestamps.sort.reverse)

      delete_entry = body["entry"].first
      expect(delete_entry.dig("request", "url")).to eq("Patient/#{first_id}")
      expect(delete_entry.dig("response", "status")).to eq("410")
      expect(delete_entry).not_to have_key("resource")

      put_entry = body["entry"].second
      expect(put_entry.dig("resource", "id")).to eq(second_id)
      expect(put_entry.dig("resource", "meta", "versionId")).to eq("2")
      expect(put_entry.dig("response", "etag")).to eq(%(W/"2"))
    end

    it "does not include versions of other resource types" do
      patient_id = create_patient
      post "/Observation", params: valid_observation_payload(subject_id: patient_id), as: :json

      get "/Patient/_history"

      expect(JSON.parse(response.body)["total"]).to eq(1)
    end

    it "pages with _count and self/previous/next links that round-trip _since" do
      create_patient
      create_patient
      create_patient

      get "/Patient/_history?_count=2&_since=2000-01-01T00:00:00Z"
      body = JSON.parse(response.body)
      expect(body["total"]).to eq(3)
      expect(body["entry"].size).to eq(2)

      links = body["link"].to_h { |l| [l["relation"], l["url"]] }
      expect(links["self"]).to include("Patient/_history?", "_count=2", "_offset=0", "_since=2000-01-01")
      expect(links).not_to have_key("previous")

      get URI.parse(links.fetch("next")).request_uri
      body = JSON.parse(response.body)
      expect(body["entry"].size).to eq(1)
      links = body["link"].to_h { |l| [l["relation"], l["url"]] }
      expect(links).to have_key("previous")
      expect(links).not_to have_key("next")
    end

    it "treats _since as inclusive (at or after the instant)" do
      create_patient
      second_id = create_patient
      cutoff = ResourceVersion.find_by(resource_id: second_id).last_updated

      get "/Patient/_history?_since=#{Rack::Utils.escape(cutoff.utc.iso8601(6))}"

      body = JSON.parse(response.body)
      expect(body["total"]).to eq(1)
      expect(body["entry"].first.dig("resource", "id")).to eq(second_id)
    end

    it "returns 400 for an unparseable _since" do
      get "/Patient/_history?_since=not-a-date"

      expect(response).to have_http_status(:bad_request)
      expect(JSON.parse(response.body)["resourceType"]).to eq("OperationOutcome")
    end

    it "returns an empty bundle when there is no history" do
      get "/Patient/_history"

      body = JSON.parse(response.body)
      expect(body["total"]).to eq(0)
      expect(body["entry"]).to eq([])
    end
  end

  describe "GET /{type}/_history with search parameters" do
    def create_request(subject_id, overrides = {})
      post "/ServiceRequest", params: valid_service_request_payload(subject_id: subject_id, **overrides), as: :json
      JSON.parse(response.body)["id"]
    end

    def child_of(header_id)
      { basedOn: [{ reference: "ServiceRequest/#{header_id}" }] }
    end

    it "returns every version of the matching resources, deleted ones included" do
      patient_id = create_patient
      header_id = create_request(patient_id)
      kept_id = create_request(patient_id, child_of(header_id))
      removed_id = create_request(patient_id, child_of(header_id))
      create_request(patient_id) # another order: not a match
      put "/ServiceRequest/#{kept_id}",
          params: valid_service_request_payload(subject_id: patient_id, status: "on-hold", **child_of(header_id)), as: :json
      delete "/ServiceRequest/#{removed_id}"

      get "/ServiceRequest/_history?based-on=ServiceRequest/#{header_id}"

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["total"]).to eq(4)
      versions = body["entry"].map { |e| [e.dig("request", "url"), e.dig("request", "method")] }
      expect(versions).to eq([
        ["ServiceRequest/#{removed_id}", "DELETE"],
        ["ServiceRequest/#{kept_id}", "PUT"],
        ["ServiceRequest/#{removed_id}", "POST"],
        ["ServiceRequest/#{kept_id}", "POST"]
      ])
    end

    it "carries the criteria in the paging links" do
      patient_id = create_patient
      header_id = create_request(patient_id)
      3.times { create_request(patient_id, child_of(header_id)) }

      get "/ServiceRequest/_history?based-on=ServiceRequest/#{header_id}&_count=2"
      links = JSON.parse(response.body)["link"].to_h { |l| [l["relation"], l["url"]] }
      expect(links["next"]).to include("based-on=ServiceRequest/#{header_id}", "_offset=2")

      get URI.parse(links.fetch("next")).request_uri
      body = JSON.parse(response.body)
      expect(body["total"]).to eq(3)
      expect(body["entry"].size).to eq(1)
    end

    it "rejects an unsupported parameter instead of widening to the whole type" do
      get "/ServiceRequest/_history?no-such-param=x"

      expect(response).to have_http_status(:bad_request)
      body = JSON.parse(response.body)
      expect(body.dig("issue", 0, "code")).to eq("not-supported")
    end

    it "lets a patient token read it within its compartment, while unfiltered stays system-only" do
      own_id = create_patient
      other_id = create_patient
      own_header = create_request(own_id)
      create_request(own_id, child_of(own_header))
      other_header = create_request(other_id)
      create_request(other_id, child_of(other_header))

      with_fhir_auth do
        token = issue_patient_token(patient_id: own_id)

        get "/ServiceRequest/_history?based-on=ServiceRequest/#{own_header}", headers: bearer_header(token)
        expect(response).to have_http_status(:ok)
        expect(JSON.parse(response.body)["total"]).to eq(1)

        get "/ServiceRequest/_history?based-on=ServiceRequest/#{other_header}", headers: bearer_header(token)
        expect(response).to have_http_status(:ok)
        expect(JSON.parse(response.body)["total"]).to eq(0)

        get "/ServiceRequest/_history", headers: bearer_header(token)
        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe "GET /_history" do
    it "mixes versions of every resource type, newest first" do
      patient_id = create_patient
      post "/Observation", params: valid_observation_payload(subject_id: patient_id), as: :json

      get "/_history"

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["type"]).to eq("history")
      expect(body["total"]).to eq(2)
      expect(body["entry"].map { |e| e.dig("resource", "resourceType") }).to eq(%w[Observation Patient])
      expect(body["entry"].first["fullUrl"]).to include("/Observation/")
    end

    it "supports _count paging and _since filtering" do
      patient_id = create_patient
      cutoff = ResourceVersion.find_by(resource_id: patient_id).last_updated
      post "/Observation", params: valid_observation_payload(subject_id: patient_id), as: :json

      get "/_history?_count=1&_since=#{Rack::Utils.escape(cutoff.utc.iso8601(6))}"

      body = JSON.parse(response.body)
      expect(body["total"]).to eq(2)
      expect(body["entry"].size).to eq(1)
      links = body["link"].to_h { |l| [l["relation"], l["url"]] }
      expect(links["next"]).to include("/_history?", "_offset=1")
      expect(links["next"]).not_to include("Patient")
    end
  end
end
