require "rails_helper"

RSpec.describe "Rate limiting (rack-attack)", type: :request do
  around do |example|
    Rack::Attack.enabled = true
    Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
    example.run
  ensure
    Rack::Attack.enabled = false
    Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
  end

  describe "OAuth endpoint per-IP throttle" do
    it "returns 429 with Retry-After and an OperationOutcome once the limit is hit" do
      limit = Rack::Attack::RATE_TOKEN_IP

      # grant_type不正は400(401ではない)なので、fail2ban側を発動させずに
      # スロットルだけを検証できる
      (limit + 1).times do
        post "/oauth/token", params: { grant_type: "authorization_code" }
      end

      expect(response).to have_http_status(:too_many_requests)
      expect(response.headers["retry-after"]).to be_present
      expect(response.content_type).to include("application/fhir+json")
      body = JSON.parse(response.body)
      expect(body["resourceType"]).to eq("OperationOutcome")
      expect(body["issue"].first["code"]).to eq("throttled")
    end
  end

  describe "auth-failure ban (fail2ban)" do
    it "bans an IP after repeated 401s" do
      with_fhir_auth do
        Fhir::AuthThrottle.max_retries.times do
          get "/Patient", headers: bearer_header("bogus-token")
          expect(response).to have_http_status(:unauthorized)
        end

        get "/Patient", headers: bearer_header("bogus-token")
        expect(response).to have_http_status(:forbidden)
        expect(JSON.parse(response.body)["issue"].first["code"]).to eq("security")

        # /up は ban 中でも到達できる
        get "/up"
        expect(response).to have_http_status(:ok)
      end
    end
  end

  describe "health check safelist" do
    it "never throttles /up" do
      (Rack::Attack::RATE_API_IP + 5).times { get "/up" }
      expect(response).to have_http_status(:ok)
    end
  end
end
