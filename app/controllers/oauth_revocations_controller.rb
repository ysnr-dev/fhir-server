# POST /oauth/revoke -- RFC 7009 トークン失効エンドポイント。
# クライアント認証は /oauth/token と同じ3方式(OauthClientAuthentication)。
# 不明なトークン・他クライアントのトークンでも 200 を返す(RFC 7009 §2.2、
# トークンの存在を推測させるオラクルにしない)。
class OauthRevocationsController < ApplicationController
  include OauthClientAuthentication

  before_action { response.set_header("Cache-Control", "no-store") }

  def create
    client, auth_error = resolve_client
    unless client
      response.set_header("WWW-Authenticate", %(Basic realm="fhir-server")) if basic_credentials
      return oauth_error(:unauthorized, "invalid_client", auth_error)
    end

    token = AccessToken.authenticate(params[:token])
    # token_type_hint は無視(発行するトークン種別が1つしかないため)
    token.update!(revoked_at: Time.current) if token && token.oauth_client_id == client.id && !token.revoked?

    head :ok
  end
end
