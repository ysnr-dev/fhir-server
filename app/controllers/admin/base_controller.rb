module Admin
  # 管理API(/admin/*)の共通基盤。
  #
  # ApplicationController ではなく ActionController::API を直接継承する:
  # ApplicationController の rescue_from は FHIR の OperationOutcome を
  # application/fhir+json で返し、ヘルパー(authorize_fhir_request! /
  # access_context)はすべて Bearer + スコープ前提になっている。管理APIは
  # FHIRリソースを扱わないので、どちらも合わない。HealthController が同じ理由で
  # ApplicationController を迂回している既存の前例に倣う。
  #
  # エラー表現は fhir-client 側の JSON 規約に合わせる(検証エラーの一覧は
  # {errors: [...]}、単一のコードは {error:, error_description:})。
  # fhir-client の backend はこのボディをそのまま透過させるので、この形は
  # 中継の前提になっている -- 変えるなら両リポジトリを同時に直すこと。
  class BaseController < ActionController::API
    # FhirAuditing は around_action + ensure なので、before_action で止まった
    # 401/503 も監査に残る。include を before_action より前に置くことが条件。
    include FhirAuditing

    # 共有トークンに識別子は無い。監査上の actor はこの固定文字列で表す。
    ACTOR_NAME = "admin-api".freeze

    rescue_from StandardError, with: :render_internal_error
    rescue_from ActionDispatch::Http::Parameters::ParseError, with: :render_malformed_json

    before_action { response.set_header("Cache-Control", "no-store") }
    before_action :require_admin_token!

    private

    def require_admin_token!
      unless Fhir::AdminAuth.enabled?
        # 設定漏れは「開いたまま」ではなく「閉じたまま」にする。認証の試行では
        # ないので、失敗としても数えない。
        return render_error(
          :service_unavailable, "admin_api_disabled",
          "FHIR_ADMIN_TOKEN is not configured on this server"
        )
      end
      return if Fhir::AdminAuth.valid?(presented_admin_token)

      # ここで意図的に Fhir::AuthThrottle.register_failure! を呼ばない。
      # auth-failure-ban の blocklist は /up 以外の全パスに効くため、呼び出し元が
      # 単一IP(fhir-client の backend)である管理APIで失敗を積むと、管理トークンを
      # 1つ間違えただけで FHIR API 全体がそのIPから 300 秒遮断される -- 自己DoS。
      # ブルートフォース対策は rack-attack の admin/ip スロットルが担う。
      response.set_header("WWW-Authenticate", %(Bearer realm="fhir-server-admin"))
      render_error(:unauthorized, "invalid_token", "Admin token missing or invalid")
    end

    def presented_admin_token
      request.headers["X-FHIR-Admin-Token"].presence ||
        request.authorization&.match(/\ABearer\s+(.+)\z/i)&.captures&.first
    end

    # --- 監査(FhirAuditing のフック上書き) ---------------------------------

    # client_id は nil のまま残す: GET /AuditEvent?agent=<client_id> は
    # 「このFHIRクライアント」を意味する検索なので、そこに管理APIを混ぜない。
    def audit_client_id
      nil
    end

    def audit_client_name
      ACTOR_NAME
    end

    # --- エラー表現 ----------------------------------------------------------

    def render_error(status, code, description)
      render json: { error: code, error_description: description }, status: status
    end

    def render_validation_errors(messages)
      render json: { errors: Array(messages) }, status: :unprocessable_content
    end

    def render_invalid_request(description)
      render_error(:bad_request, "invalid_request", description)
    end

    def render_not_found(description)
      render_error(:not_found, "not_found", description)
    end

    def render_malformed_json(exception)
      render_invalid_request("Malformed JSON: #{exception.message}")
    end

    def render_internal_error(exception)
      # rescue_from が全例外を握るためSentryのRackミドルウェアには届かない。
      Sentry.capture_exception(exception) if defined?(Sentry) && Sentry.initialized?
      Rails.logger.error("#{exception.class}: #{exception.message}\n#{exception.backtrace&.first(10)&.join("\n")}")
      render_error(
        :internal_server_error, "internal_error",
        Rails.env.production? ? "An internal error occurred" : exception.message
      )
    end
  end
end
