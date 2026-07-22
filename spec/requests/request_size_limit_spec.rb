require "rails_helper"

RSpec.describe "Request size limit", type: :request do
  around do |example|
    RequestSizeLimiter.max_bytes = 1024
    example.run
  ensure
    RequestSizeLimiter.max_bytes = nil
  end

  it "rejects an oversized body with 413 and an OperationOutcome" do
    post "/Patient",
         params: { "resourceType" => "Patient", "name" => [{ "text" => "x" * 2048 }] }.to_json,
         headers: { "CONTENT_TYPE" => "application/fhir+json" }

    expect(response).to have_http_status(:content_too_large)
    expect(response.content_type).to include("application/fhir+json")
    body = JSON.parse(response.body)
    expect(body["resourceType"]).to eq("OperationOutcome")
    expect(body["issue"].first["code"]).to eq("too-long")
  end

  it "allows bodies within the limit" do
    post "/Patient",
         params: valid_patient_payload.to_json,
         headers: { "CONTENT_TYPE" => "application/fhir+json" }

    expect(response).to have_http_status(:created)
  end
end
