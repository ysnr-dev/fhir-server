require "rails_helper"

# Cross-cutting FHIR_PROFILE_VALIDATION mode behavior (Fhir::Profile.mode),
# exercised through Patient as the representative resource. Per-check
# coverage of the engine itself lives in spec/lib/fhir/profile/validator_spec.rb;
# this file only asserts how each mode wires into the HTTP write path.
RSpec.describe "JP Core profile validation modes", type: :request do
  def payload_with_unknown_field
    valid_patient_payload(notARealField: "oops")
  end

  describe "mode :warn (default)" do
    it "does not block create; the hand validator alone still can" do
      post "/Patient", params: payload_with_unknown_field, as: :json

      expect(response).to have_http_status(:created)
    end
  end

  describe "mode :enforce" do
    it "blocks create with a 422 merging profile issues into the OperationOutcome" do
      with_profile_mode(:enforce) do
        post "/Patient", params: payload_with_unknown_field, as: :json
      end

      expect(response).to have_http_status(:unprocessable_content)
      body = JSON.parse(response.body)
      expect(body["issue"]).to include(a_hash_including("code" => "structure", "diagnostics" => a_string_including("notARealField")))
    end

    it "still allows a conformant create" do
      with_profile_mode(:enforce) do
        post "/Patient", params: valid_patient_payload, as: :json
      end

      expect(response).to have_http_status(:created)
    end

    it "blocks update the same way" do
      post "/Patient", params: valid_patient_payload, as: :json
      id = JSON.parse(response.body)["id"]

      with_profile_mode(:enforce) do
        put "/Patient/#{id}", params: payload_with_unknown_field, as: :json
      end

      expect(response).to have_http_status(:unprocessable_content)
      expect(JSON.parse(response.body)["issue"]).to include(a_hash_including("code" => "structure"))
    end

    it "merges hand-validator and profile issues into a single 422 when both fail" do
      with_profile_mode(:enforce) do
        post "/Patient", params: payload_with_unknown_field.except("identifier"), as: :json
      end

      expect(response).to have_http_status(:unprocessable_content)
      issues = JSON.parse(response.body)["issue"]
      expect(issues).to include(a_hash_including("code" => "required")) # hand validator: missing identifier
      expect(issues).to include(a_hash_including("code" => "structure")) # profile engine: unknown field
    end

    it "still blocks a patch that results in a profile violation" do
      post "/Patient", params: valid_patient_payload, as: :json
      id = JSON.parse(response.body)["id"]

      with_profile_mode(:enforce) do
        patch "/Patient/#{id}", params: [{ "op" => "add", "path" => "/notARealField", "value" => "oops" }].to_json,
                                 headers: { "CONTENT_TYPE" => "application/json-patch+json" }
      end

      expect(response).to have_http_status(:unprocessable_content)
      expect(JSON.parse(response.body)["issue"]).to include(a_hash_including("code" => "structure"))
    end
  end

  describe "mode :off" do
    it "never blocks on profile issues even if explicitly requested via $validate" do
      with_profile_mode(:off) do
        post "/Patient/$validate", params: payload_with_unknown_field, as: :json
      end

      expect(JSON.parse(response.body)["issue"].map { |i| i["severity"] }).to eq(["information"])
    end
  end
end
