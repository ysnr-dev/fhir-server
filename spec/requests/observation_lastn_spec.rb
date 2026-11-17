require "rails_helper"

RSpec.describe "Observation/$lastn", type: :request do
  let(:hemoglobin) { { "system" => "http://loinc.org", "code" => "718-7", "display" => "Hemoglobin" } }
  let(:glucose) { { "system" => "http://loinc.org", "code" => "2345-7", "display" => "Glucose" } }

  def create_patient
    post "/Patient", params: valid_patient_payload, as: :json
    JSON.parse(response.body)["id"]
  end

  # coding: nil makes a text-only code.
  def create_observation(patient_id, coding:, effective:, text: nil, status: "final")
    payload = valid_observation_payload(subject_id: patient_id, "status" => status)
    payload["code"] = { "coding" => coding ? [coding] : nil, "text" => text || coding&.fetch("display") }.compact
    effective ? payload["effectiveDateTime"] = effective : payload.delete("effectiveDateTime")
    post "/Observation", params: payload, as: :json
    expect(response).to have_http_status(:created), response.body
    JSON.parse(response.body)["id"]
  end

  def bundle
    JSON.parse(response.body)
  end

  def match_ids
    bundle.fetch("entry", []).select { |e| e.dig("search", "mode") == "match" }.map { |e| e.dig("resource", "id") }
  end

  let!(:patient) { create_patient }
  let!(:hb_old) { create_observation(patient, coding: hemoglobin, effective: "2026-07-01T10:00:00+09:00") }
  let!(:hb_mid) { create_observation(patient, coding: hemoglobin, effective: "2026-07-10T10:00:00+09:00") }
  let!(:hb_new) { create_observation(patient, coding: hemoglobin, effective: "2026-07-20T10:00:00+09:00") }
  let!(:glu_old) { create_observation(patient, coding: glucose, effective: "2026-07-05T10:00:00+09:00") }
  let!(:glu_new) { create_observation(patient, coding: glucose, effective: "2026-07-15T10:00:00+09:00") }

  it "returns the latest observation per code by default" do
    get "/Observation/$lastn?patient=Patient/#{patient}"

    expect(response).to have_http_status(:ok)
    expect(bundle["type"]).to eq("searchset")
    expect(bundle["total"]).to eq(2)
    expect(match_ids).to contain_exactly(hb_new, glu_new)
  end

  it "returns up to max per code, grouped by code and newest first within it" do
    get "/Observation/$lastn?patient=Patient/#{patient}&max=2"

    expect(bundle["total"]).to eq(4)
    # 2345-7 sorts before 718-7; newest first inside each group.
    expect(match_ids).to eq([glu_new, glu_old, hb_new, hb_mid])
  end

  it "applies ordinary search parameters before picking the latest" do
    get "/Observation/$lastn?patient=Patient/#{patient}&date=lt2026-07-12"
    expect(match_ids).to contain_exactly(hb_mid, glu_old)

    get "/Observation/$lastn?patient=Patient/#{patient}&code=718-7&max=5"
    expect(match_ids).to eq([hb_new, hb_mid, hb_old])
  end

  it "keeps patients apart only through the search criteria" do
    other = create_patient
    other_hb = create_observation(other, coding: hemoglobin, effective: "2026-08-01T10:00:00+09:00")

    get "/Observation/$lastn?patient=Patient/#{other}"
    expect(match_ids).to eq([other_hb])

    get "/Observation/$lastn?patient=Patient/#{patient}"
    expect(match_ids).to contain_exactly(hb_new, glu_new)
  end

  it "separates the same code in different systems and falls back to code.text" do
    local = create_observation(patient, coding: { "system" => "http://example.org/local", "code" => "718-7", "display" => "Hb" },
                                        effective: "2026-06-01T10:00:00+09:00")
    text_old = create_observation(patient, coding: nil, text: "身長", effective: "2026-06-01T10:00:00+09:00")
    text_new = create_observation(patient, coding: nil, text: "身長", effective: "2026-06-02T10:00:00+09:00")

    get "/Observation/$lastn?patient=Patient/#{patient}"

    expect(match_ids).to contain_exactly(hb_new, glu_new, local, text_new)
    expect(match_ids).not_to include(text_old)
  end

  it "ranks an observation without a date after the dated ones" do
    undated = create_observation(patient, coding: glucose, effective: nil)

    get "/Observation/$lastn?patient=Patient/#{patient}&code=2345-7&max=3"

    expect(match_ids).to eq([glu_new, glu_old, undated])
  end

  it "pages with links that stay on $lastn and keep max" do
    get "/Observation/$lastn?patient=Patient/#{patient}&max=2&_count=3"

    expect(bundle["entry"].size).to eq(3)
    next_link = bundle["link"].find { |l| l["relation"] == "next" }
    uri = URI.parse(next_link["url"])
    expect(uri.path).to eq("/Observation/$lastn")
    expect(uri.query).to include("max=2", "_offset=3")

    get uri.request_uri
    expect(match_ids).to eq([hb_mid])
  end

  it "supports _summary=count and _include" do
    get "/Observation/$lastn?patient=Patient/#{patient}&_summary=count"
    expect(bundle["total"]).to eq(2)
    expect(bundle).not_to have_key("entry")

    get "/Observation/$lastn?patient=Patient/#{patient}&_include=Observation:subject"
    included = bundle["entry"].select { |e| e.dig("search", "mode") == "include" }
    expect(included.map { |e| e.dig("resource", "id") }).to eq([patient])
  end

  it "rejects an invalid max" do
    %w[0 -1 abc 101].each do |max|
      get "/Observation/$lastn?max=#{max}"
      expect(response).to have_http_status(:bad_request), "max=#{max}"
    end
  end

  it "rejects unknown parameters and _sort only under handling=strict" do
    get "/Observation/$lastn?no-such-param=1&_sort=date"
    expect(response).to have_http_status(:ok)

    get "/Observation/$lastn?no-such-param=1", headers: { "Prefer" => "handling=strict" }
    expect(response).to have_http_status(:bad_request)

    get "/Observation/$lastn?_sort=date", headers: { "Prefer" => "handling=strict" }
    expect(response).to have_http_status(:bad_request)

    get "/Observation/$lastn?max=2", headers: { "Prefer" => "handling=strict" }
    expect(response).to have_http_status(:ok)
  end

  it "is not routed for other types" do
    get "/Condition/$lastn"

    expect(response).to have_http_status(:not_found)
  end

  it "is audited as an operation and advertised in the CapabilityStatement" do
    get "/Observation/$lastn?patient=Patient/#{patient}"
    expect(AuditEvent.order(:occurred_at).last.interaction).to eq("operation")

    get "/metadata"
    observation = bundle.dig("rest", 0, "resource").find { |r| r["type"] == "Observation" }
    expect(observation["operation"].map { |o| o["name"] }).to include("lastn")
  end

  it "confines a patient-context token to its own compartment" do
    other = create_patient
    create_observation(other, coding: hemoglobin, effective: "2026-08-01T10:00:00+09:00")

    with_fhir_auth do
      get "/Observation/$lastn", headers: bearer_header(issue_patient_token(patient_id: patient))
      expect(match_ids).to contain_exactly(hb_new, glu_new)

      get "/Observation/$lastn", headers: bearer_header(issue_access_token(scopes: "system/Patient.read"))
      expect(response).to have_http_status(:forbidden)
    end
  end
end
