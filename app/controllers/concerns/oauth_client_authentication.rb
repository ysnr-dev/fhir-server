# /oauth/token と /oauth/revoke で共通のクライアント認証。
# private_key_jwt / client_secret_basic / client_secret_post の3方式。
module OauthClientAuthentication
  extend ActiveSupport::Concern

  private

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
      result.valid? ? [result.client, nil] : [nil, result.error_description]
    else
      client = basic_credentials ? OauthClient.authenticate(*basic_credentials) : OauthClient.authenticate(params[:client_id], params[:client_secret])
      client ? [client, nil] : [nil, "Client authentication failed"]
    end
  end

  def basic_credentials
    return nil unless request.authorization&.match?(/\ABasic /i)

    @basic_credentials ||= Base64.decode64(request.authorization.split(" ", 2).last.to_s).split(":", 2)
  end

  def oauth_error(status, error, description)
    render json: { error: error, error_description: description }, status: status
  end
end
