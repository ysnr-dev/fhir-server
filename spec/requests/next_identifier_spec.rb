require "rails_helper"

RSpec.describe "$next-identifier operation", type: :request do
  let(:system) { "http://fhir-client.local/patient-number" }

  def create_patient_with_number(value, system: self.system)
    payload = valid_patient_payload("identifier" => [{ "system" => system, "value" => value }])
    post "/Patient", params: payload, as: :json
    expect(response).to have_http_status(:created)
    JSON.parse(response.body)["id"]
  end

  def next_value
    get "/Patient/$next-identifier", params: { system: system }
    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    expect(body["resourceType"]).to eq("Parameters")
    expect(body["parameter"].find { |p| p["name"] == "system" }["valueUri"]).to eq(system)
    body["parameter"].find { |p| p["name"] == "value" }["valueString"]
  end

  it "starts at 1 when nothing is registered" do
    expect(next_value).to eq("1")
  end

  it "continues from the largest registered number, comparing numerically" do
    create_patient_with_number("9")
    create_patient_with_number("10")

    expect(next_value).to eq("11")
  end

  it "never returns the same number twice, even before the previous one is registered" do
    create_patient_with_number("5")

    expect(next_value).to eq("6")
    expect(next_value).to eq("7")

    # 払い出した番号で登録すると、その次から続く。
    create_patient_with_number("7")
    expect(next_value).to eq("8")
  end

  it "skips past a larger number registered by hand" do
    expect(next_value).to eq("1")
    create_patient_with_number("100")

    expect(next_value).to eq("101")
  end

  it "ignores non-numeric values, other systems and other resource types" do
    create_patient_with_number("ABC-3")
    create_patient_with_number("50", system: "http://example.org/other")
    post "/Organization", params: { "resourceType" => "Organization", "name" => "x",
                                    "identifier" => [{ "system" => system, "value" => "500" }] }, as: :json
    expect(response).to have_http_status(:created)

    expect(next_value).to eq("1")
  end

  it "does not reuse the number of a deleted patient" do
    id = create_patient_with_number("3")
    delete "/Patient/#{id}"
    expect(response).to have_http_status(:no_content)

    expect(next_value).to eq("4")
  end

  it "returns 400 without system" do
    get "/Patient/$next-identifier"

    expect(response).to have_http_status(:bad_request)
    expect(JSON.parse(response.body)["issue"].first["code"]).to eq("invalid")
  end

  it "requires write scope when auth is enabled" do
    with_fhir_auth do
      get "/Patient/$next-identifier", params: { system: system },
                                        headers: bearer_header(issue_access_token(scopes: "system/Patient.read"))
      expect(response).to have_http_status(:forbidden)

      get "/Patient/$next-identifier", params: { system: system },
                                        headers: bearer_header(issue_access_token(scopes: "system/Patient.write"))
      expect(response).to have_http_status(:ok)
    end
  end
end
