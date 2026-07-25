require "rails_helper"

# 管理APIの認証は書き込み経路より先にここで固める。GET /admin/scopes は
# 副作用が無いので、fail closed の挙動だけを純粋に確認できる。
RSpec.describe "Admin scope options (GET /admin/scopes)", type: :request do
  let(:admin_token) { "a" * 64 }

  def with_admin_token(token = admin_token)
    previous = ENV["FHIR_ADMIN_TOKEN"]
    ENV["FHIR_ADMIN_TOKEN"] = token
    yield
  ensure
    ENV["FHIR_ADMIN_TOKEN"] = previous
  end

  def admin_headers
    { "X-FHIR-Admin-Token" => admin_token }
  end

  describe "when FHIR_ADMIN_TOKEN is not configured" do
    it "answers 503 rather than serving the endpoint" do
      with_admin_token(nil) { get "/admin/scopes" }

      expect(response).to have_http_status(:service_unavailable)
      expect(JSON.parse(response.body)["error"]).to eq("admin_api_disabled")
      # 資格情報を要求しているのではなく機能が無効なので、チャレンジは返さない
      expect(response.headers["WWW-Authenticate"]).to be_nil
    end
  end

  describe "authentication" do
    it "rejects a request with no token" do
      with_admin_token { get "/admin/scopes" }

      expect(response).to have_http_status(:unauthorized)
      expect(JSON.parse(response.body)["error"]).to eq("invalid_token")
      expect(response.headers["WWW-Authenticate"]).to include("fhir-server-admin")
    end

    it "rejects a wrong token in either header form" do
      with_admin_token do
        get "/admin/scopes", headers: { "X-FHIR-Admin-Token" => "wrong" }
        expect(response).to have_http_status(:unauthorized)

        get "/admin/scopes", headers: { "Authorization" => "Bearer wrong" }
        expect(response).to have_http_status(:unauthorized)
      end
    end

    it "accepts the correct token in either header form" do
      with_admin_token do
        get "/admin/scopes", headers: admin_headers
        expect(response).to have_http_status(:ok)

        get "/admin/scopes", headers: { "Authorization" => "Bearer #{admin_token}" }
        expect(response).to have_http_status(:ok)
      end
    end

    # 管理APIは Fhir::Auth.enabled? を参照しない。認証OFFが既定の開発環境でも
    # 閉じていること、有効化しても振る舞いが変わらないことの両方を固定する。
    it "fails closed whether or not FHIR auth is enabled" do
      with_admin_token do
        get "/admin/scopes"
        expect(response).to have_http_status(:unauthorized)

        with_fhir_auth { get "/admin/scopes" }
        expect(response).to have_http_status(:unauthorized)

        with_fhir_auth { get "/admin/scopes", headers: admin_headers }
        expect(response).to have_http_status(:ok)
      end
    end

    it "does not ban the caller's IP after repeated failures" do
      # 呼び出し元は単一IPの中継サーバーなので、ここでBANするとFHIR API全体が
      # 落ちる。auth-failure-ban に積まないことをカウンタ経由で確認する。
      with_admin_token do
        expect(Fhir::AuthThrottle).not_to receive(:register_failure!)

        3.times { get "/admin/scopes", headers: { "X-FHIR-Admin-Token" => "wrong" } }
      end
    end
  end

  describe "the payload" do
    subject(:body) do
      with_admin_token { get "/admin/scopes", headers: admin_headers }
      JSON.parse(response.body)
    end

    it "labels the wildcard and every supported resource type" do
      types = body["resource_types"]

      expect(types.first).to eq({ "type" => "*", "label" => "すべての診療記録" })
      expect(types.map { |t| t["type"] }).to include(*Fhir::ResourceRegistry.types)
      expect(types.map { |t| t["label"] }).to all(be_present)
    end

    it "offers write access only on the system family" do
      expect(body["system_access"].map { |a| a["value"] }).to eq(%w[read write *])
      expect(body["patient_access"].map { |a| a["value"] }).to eq(%w[read])
    end

    it "labels every context scope" do
      scopes = body["context_scopes"]

      expect(scopes.map { |s| s["scope"] }).to eq(Fhir::Scopes::CONTEXT_SCOPES)
      expect(scopes.map { |s| s["label"] }).to all(be_present)
    end

    it "is not cacheable" do
      with_admin_token { get "/admin/scopes", headers: admin_headers }

      expect(response.headers["Cache-Control"]).to include("no-store")
    end

    it "records no audit event" do
      expect { with_admin_token { get "/admin/scopes", headers: admin_headers } }
        .not_to change(AuditEvent, :count)
    end
  end
end
