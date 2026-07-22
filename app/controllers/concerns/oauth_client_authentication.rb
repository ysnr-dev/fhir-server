# /oauth/token と /oauth/revoke で共通のクライアント認証。
# private_key_jwt / client_secret_basic / client_secret_post の3方式。
# あわせて監査(FhirAuditing)も有効化する: 認証成功時は @audited_client で
# クライアントを特定、失敗時(401/400)は client=nil のまま記録され、
# ブルートフォースの痕跡が監査証跡に残る。
module OauthClientAuthentication
  extend ActiveSupport::Concern
  include FhirAuditing

  private

  def audit_interaction
    "operation"
  end

  def audit_client_id
    @audited_client&.id
  end

  def audit_client_name
    @audited_client&.name
  end

  # Returns [client, nil] or [nil, error_description]. A request presenting a
  # client_assertion is authenticated via private_key_jwt; otherwise the
  # symmetric secret paths (Basic / body params) apply.
  def resolve_client
    if params[:client_assertion].present? || params[:client_assertion_type].present?
      result = Fhir::ClientAssertion.call(
        params[:client_assertion],
        assertion_type: params[:client_assertion_type],
        # 失効エンドポイントでも audience はトークンエンドポイント(SMARTの慣例)
        audience: "#{base_url}/oauth/token"
      )
      if result.valid?
        [@audited_client = result.client, nil]
      else
        [nil, result.error_description]
      end
    else
      client = basic_credentials ? OauthClient.authenticate(*basic_credentials) : OauthClient.authenticate(params[:client_id], params[:client_secret])
      client ? [@audited_client = client, nil] : [nil, "Client authentication failed"]
    end
  end

  def basic_credentials
    return nil unless request.authorization&.match?(/\ABasic /i)

    @basic_credentials ||= Base64.decode64(request.authorization.split(" ", 2).last.to_s).split(":", 2)
  end

  def oauth_error(status, error, description)
    Fhir::AuthThrottle.register_failure!(request.remote_ip) if status == :unauthorized
    render json: { error: error, error_description: description }, status: status
  end
end
