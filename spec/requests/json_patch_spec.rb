require "rails_helper"

RSpec.describe "JSON Patch (PATCH /{type}/:id)", type: :request do
  PATCH_HEADERS = { "CONTENT_TYPE" => "application/json-patch+json" }.freeze

  def create_patient(overrides = {})
    post "/Patient", params: valid_patient_payload(overrides), as: :json
    JSON.parse(response.body)["id"]
  end

  def patch_patient(id, operations, headers: {})
    patch "/Patient/#{id}", params: operations.to_json, headers: PATCH_HEADERS.merge(headers)
  end

  it "applies a patch, bumping the version like a normal update" do
    id = create_patient

    patch_patient(id, [{ "op" => "replace", "path" => "/gender", "value" => "female" }])

    expect(response).to have_http_status(:ok)
    expect(response.headers["ETag"]).to eq(%(W/"2"))
    body = JSON.parse(response.body)
    expect(body["gender"]).to eq("female")
    expect(body["meta"]["versionId"]).to eq("2")
    expect(body["name"]).to be_present # untouched fields survive

    get "/Patient/#{id}/_history"
    expect(JSON.parse(response.body)["total"]).to eq(2)
  end

  it "supports a guarded update via a test op" do
    id = create_patient

    patch_patient(id, [
      { "op" => "test", "path" => "/gender", "value" => "male" },
      { "op" => "replace", "path" => "/gender", "value" => "other" }
    ])

    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body)["gender"]).to eq("other")
  end

  it "returns 415 for a non-JSON-Patch content type" do
    id = create_patient

    patch "/Patient/#{id}", params: [{ "op" => "remove", "path" => "/gender" }].to_json,
                            headers: { "CONTENT_TYPE" => "application/fhir+json" }

    expect(response).to have_http_status(:unsupported_media_type)
  end

  it "returns 400 for a body that is not a JSON array" do
    id = create_patient

    patch "/Patient/#{id}", params: { "op" => "remove", "path" => "/gender" }.to_json, headers: PATCH_HEADERS

    expect(response).to have_http_status(:bad_request)
  end

  it "returns 400 for an unknown op" do
    id = create_patient

    patch_patient(id, [{ "op" => "merge", "path" => "/gender", "value" => "female" }])

    expect(response).to have_http_status(:bad_request)
    expect(JSON.parse(response.body)["issue"][0]["code"]).to eq("structure")
  end

  it "returns 422 when a test op fails, leaving the resource unchanged" do
    id = create_patient

    patch_patient(id, [
      { "op" => "test", "path" => "/gender", "value" => "female" },
      { "op" => "replace", "path" => "/gender", "value" => "other" }
    ])

    expect(response).to have_http_status(:unprocessable_content)
    expect(JSON.parse(response.body)["issue"][0]["code"]).to eq("processing")

    get "/Patient/#{id}"
    body = JSON.parse(response.body)
    expect(body["gender"]).to eq("male")
    expect(body["meta"]["versionId"]).to eq("1")
  end

  it "returns 422 when removing a nonexistent path" do
    id = create_patient

    patch_patient(id, [{ "op" => "remove", "path" => "/maritalStatus" }])

    expect(response).to have_http_status(:unprocessable_content)
  end

  it "returns 400 when the patch changes resourceType" do
    id = create_patient

    patch_patient(id, [{ "op" => "replace", "path" => "/resourceType", "value" => "Observation" }])

    expect(response).to have_http_status(:bad_request)
  end

  it "returns 422 when the patched resource fails FHIR validation" do
    id = create_patient

    patch_patient(id, [{ "op" => "replace", "path" => "/gender", "value" => "invalid-gender" }])

    expect(response).to have_http_status(:unprocessable_content)
  end

  it "honors If-Match: applies on the current version, 412 on a stale one" do
    id = create_patient

    patch_patient(id, [{ "op" => "replace", "path" => "/gender", "value" => "female" }],
                  headers: { "If-Match" => %(W/"1") })
    expect(response).to have_http_status(:ok)

    patch_patient(id, [{ "op" => "replace", "path" => "/gender", "value" => "male" }],
                  headers: { "If-Match" => %(W/"1") })
    expect(response).to have_http_status(:precondition_failed)
  end

  it "returns 404 for an unknown id" do
    patch_patient("no-such-id", [{ "op" => "replace", "path" => "/gender", "value" => "female" }])

    expect(response).to have_http_status(:not_found)
  end

  it "returns 410 for a deleted resource" do
    id = create_patient
    delete "/Patient/#{id}"

    patch_patient(id, [{ "op" => "replace", "path" => "/gender", "value" => "female" }])

    expect(response).to have_http_status(:gone)
  end
end
