require "rails_helper"

RSpec.describe "Rate limiting (rack-attack)", type: :request do
  # スロットルのカウンタキーは (現在時刻 / period) を含む。上限ぎりぎりまで撃つ
  # テストは分境界を跨いだ瞬間にカウンタがリセットされて偶発的に落ちるので、
  # 時刻を止めてから実行する。
  around do |example|
    Rack::Attack.enabled = true
    Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
    freeze_time { example.run }
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

  describe "admin API per-IP throttle" do
    # 管理APIの401は auth-failure-ban に積まない(呼び出し元が単一IPの中継サーバー
    # なので、積むと管理トークンの打ち間違いでFHIR API全体が遮断される)。
    # 共有トークンへのブルートフォースを止めるのはこのスロットルだけ。
    around do |example|
      previous = ENV["FHIR_ADMIN_TOKEN"]
      ENV["FHIR_ADMIN_TOKEN"] = "a" * 64
      example.run
    ensure
      ENV["FHIR_ADMIN_TOKEN"] = previous
    end

    def wrong_token_request
      get "/admin/oauth_clients", headers: { "X-FHIR-Admin-Token" => "wrong" }
    end

    it "returns 429 from the admin rule, not the FHIR api rule" do
      Rack::Attack::RATE_ADMIN_IP.times do
        wrong_token_request
        expect(response).to have_http_status(:unauthorized)
      end

      wrong_token_request

      expect(response).to have_http_status(:too_many_requests)
      expect(request.env["rack.attack.matched"]).to eq("admin/ip")
      expect(JSON.parse(response.body)["issue"].first["code"]).to eq("throttled")
    end

    it "does not ban the caller's IP after repeated 401s" do
      (Fhir::AuthThrottle.max_retries + 1).times { wrong_token_request }

      expect(Fhir::AuthThrottle.banned?("127.0.0.1")).to be(false)
      # BANされていれば /metadata も 403 になる
      get "/metadata"
      expect(response).to have_http_status(:ok)
    end
  end

  describe "health check safelist" do
    it "never throttles /up" do
      (Rack::Attack::RATE_API_IP + 5).times { get "/up" }
      expect(response).to have_http_status(:ok)
    end
  end
end
