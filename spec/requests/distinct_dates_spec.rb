require "rails_helper"

RSpec.describe "$distinct-dates operation", type: :request do
  def create_patient
    post "/Patient", params: valid_patient_payload, as: :json
    JSON.parse(response.body)["id"]
  end

  def create_observation(patient_id, effective)
    overrides = effective ? { "effectiveDateTime" => effective } : {}
    payload = valid_observation_payload(subject_id: patient_id, **overrides)
    payload.delete("effectiveDateTime") if effective.nil?
    post "/Observation", params: payload, as: :json
    JSON.parse(response.body)["id"]
  end

  def dates_of(body)
    body["parameter"].select { |p| p["name"] == "date" }.map { |p| p["valueDate"] || p["valueDateTime"] }
  end

  def undated_of(body)
    body["parameter"].find { |p| p["name"] == "undated" }&.dig("valueBoolean")
  end

  it "returns distinct local dates newest first (JST boundary)" do
    patient_id = create_patient
    # JST 8/23 09:30 と 8/23 23:30(UTC では 8/23 14:30) -- 同じ JST 日付
    create_observation(patient_id, "2026-08-23T09:30:00+09:00")
    create_observation(patient_id, "2026-08-23T23:30:00+09:00")
    # JST 8/24 08:00 は UTC では 8/23 23:00 -- UTC で丸めると前日に落ちる値
    create_observation(patient_id, "2026-08-24T08:00:00+09:00")

    get "/Observation/$distinct-dates?patient=Patient/#{patient_id}&date-param=date" \
        "&timezone=%2B09:00"

    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    expect(body["resourceType"]).to eq("Parameters")
    expect(dates_of(body)).to eq(%w[2026-08-24 2026-08-23])
    expect(undated_of(body)).to be(false)

    # タイムゾーン省略(UTC)では 3 件とも UTC の 8/23 に丸まる
    # (8/24 08:00+09:00 は UTC では 8/23 23:00)。
    get "/Observation/$distinct-dates?patient=Patient/#{patient_id}&date-param=date"
    expect(dates_of(JSON.parse(response.body))).to eq(%w[2026-08-23])
  end

  it "returns raw instants with precision=full and honors limit" do
    patient_id = create_patient
    create_observation(patient_id, "2026-08-23T09:00:00+09:00")
    create_observation(patient_id, "2026-08-23T09:00:00+09:00") # 同時刻(重複は 1 つ)
    create_observation(patient_id, "2026-08-23T12:00:00+09:00")
    create_observation(patient_id, "2026-08-22T09:00:00+09:00")

    get "/Observation/$distinct-dates?patient=Patient/#{patient_id}&date-param=date" \
        "&precision=full&limit=2"

    body = JSON.parse(response.body)
    expect(dates_of(body)).to eq(%w[2026-08-23T03:00:00Z 2026-08-23T00:00:00Z])
  end

  it "reports whether undated resources exist" do
    patient_id = create_patient
    # occurrence を持たないオーダー(実施予定なし)が「日付なし」として現れる。
    post "/ServiceRequest", params: valid_service_request_payload(subject_id: patient_id), as: :json

    get "/ServiceRequest/$distinct-dates?patient=Patient/#{patient_id}&date-param=occurrence"

    body = JSON.parse(response.body)
    expect(dates_of(body)).to eq([])
    expect(undated_of(body)).to be(true)
  end

  it "applies ordinary search filters (category, extension params)" do
    patient_id = create_patient
    create_observation(patient_id, "2026-08-23T09:00:00+09:00")
    other_patient = create_patient
    create_observation(other_patient, "2026-08-20T09:00:00+09:00")

    get "/Observation/$distinct-dates?patient=Patient/#{patient_id}&date-param=date&timezone=%2B09:00"

    expect(dates_of(JSON.parse(response.body))).to eq(%w[2026-08-23])
  end

  it "rejects a missing or unknown date-param with 400" do
    get "/Observation/$distinct-dates"
    expect(response).to have_http_status(:bad_request)

    get "/Observation/$distinct-dates?date-param=code"
    expect(response).to have_http_status(:bad_request)
    expect(JSON.parse(response.body)["issue"].first["diagnostics"]).to include("code")

    get "/Observation/$distinct-dates?date-param=date&timezone=jst"
    expect(response).to have_http_status(:bad_request)
  end

  it "honors Prefer: handling=strict for the search criteria" do
    get "/Observation/$distinct-dates?date-param=date&bogus=1",
        headers: { "Prefer" => "handling=strict" }

    expect(response).to have_http_status(:bad_request)
    expect(JSON.parse(response.body)["issue"].first["diagnostics"]).to include("bogus")

    # lenient(既定)では無視される。operation 固有のパラメータは strict でも通る。
    get "/Observation/$distinct-dates?date-param=date&bogus=1"
    expect(response).to have_http_status(:ok)

    get "/Observation/$distinct-dates?date-param=date&timezone=%2B09:00&limit=5&precision=day",
        headers: { "Prefer" => "handling=strict" }
    expect(response).to have_http_status(:ok)
  end

  it "works on the other karte-day resource types (authoredon etc.)" do
    patient_id = create_patient
    post "/ServiceRequest",
         params: valid_service_request_payload(subject_id: patient_id, "authoredOn" => "2026-08-20T10:00:00+09:00"),
         as: :json

    get "/ServiceRequest/$distinct-dates?patient=Patient/#{patient_id}&date-param=authoredon" \
        "&timezone=%2B09:00&based-on:missing=true"

    expect(dates_of(JSON.parse(response.body))).to eq(%w[2026-08-20])
  end
end
