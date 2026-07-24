# POST /oauth/introspect -- RFC 7662 トークンイントロスペクション。
#
# revoke と同じ3方式(OauthClientAuthentication)でクライアントを認証するが、
# こちらは scope / sub / exp などトークンのメタデータを開示するため、RFC 7662
# §2.1 が要求する「何らかの認可」を厳格に満たす: publicクライアントのバイパスは
# 設けず、認証できないリクエストは 401 で拒否する。認証済みクライアントは、
# 自分以外のクライアントに発行されたトークンも照会できる(リソースサーバが
# 受け取ったトークンを検証する典型的なユースケース。生トークンの所持が前提で
# あり、それを持つ者はトークンを直接使えるので追加の漏洩はない)。
#
# token_type_hint は無視して access / refresh の両方を照合する(RFC 7662 §2.1 で
# 許容)。不明・失効・期限切れ・使用済みのトークンは、その事実を推測させる
# オラクルにしないため一律 {"active": false} を返す(RFC 7662 §2.2, §4)。
class OauthIntrospectionsController < ApplicationController
  include OauthClientAuthentication

  before_action { response.set_header("Cache-Control", "no-store") }

  INACTIVE = { active: false }.freeze

  def create
    client, auth_error = resolve_client
    unless client
      response.set_header("WWW-Authenticate", %(Basic realm="fhir-server")) if basic_credentials
      return oauth_error(:unauthorized, "invalid_client", auth_error)
    end

    # token だけは必須パラメータ(RFC 7662 §2.1)。欠落は request エラーで、
    # 不明なトークン({active:false})とは区別する。
    return oauth_error(:bad_request, "invalid_request", "token parameter is required") if params[:token].blank?

    render json: introspect(params[:token])
  end

  private

  def introspect(raw)
    if (token = AccessToken.authenticate(raw))
      access_token_claims(token)
    elsif (refresh = RefreshToken.authenticate(raw))
      refresh_token_claims(refresh)
    else
      INACTIVE
    end
  end

  def access_token_claims(token)
    return INACTIVE if token.revoked? || token.expired?

    # scope は発行時に付与した文字列そのまま(トークンエンドポイントが返した値と
    # 一致)。sub / patient はBackendServicesトークンでは nil になり compact で
    # 落ちる。
    base_claims(token).merge(token_type: "bearer").compact
  end

  def refresh_token_claims(refresh)
    return INACTIVE if refresh.used? || refresh.revoked? || refresh.expired?

    base_claims(refresh).compact
  end

  def base_claims(token)
    {
      active: true,
      scope: token.scopes,
      client_id: token.oauth_client_id,
      exp: token.expires_at.to_i,
      iat: token.created_at.to_i,
      sub: token.user_id,
      aud: base_url,
      iss: base_url,
      # SMART launch context: このトークンが紐づく患者。system トークンでは nil。
      patient: token.patient_id
    }
  end
end
