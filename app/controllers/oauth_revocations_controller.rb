# POST /oauth/revoke -- RFC 7009 トークン失効エンドポイント。
# クライアント認証は /oauth/token と同じ3方式(OauthClientAuthentication)。
# 不明なトークン・他クライアントのトークンでも 200 を返す(RFC 7009 §2.2、
# トークンの存在を推測させるオラクルにしない)。
class OauthRevocationsController < ApplicationController
  include OauthClientAuthentication

  before_action { response.set_header("Cache-Control", "no-store") }

  def create
    client, auth_error = resolve_client_or_public
    unless client
      response.set_header("WWW-Authenticate", %(Basic realm="fhir-server")) if basic_credentials
      return oauth_error(:unauthorized, "invalid_client", auth_error)
    end

    # token_type_hint は無視して両方の種別を照合する(RFC 7009 §2.1 で許容。
    # digest検索が2回になるだけで、ヒントに従うより単純)。
    if (token = AccessToken.authenticate(params[:token]))
      token.update!(revoked_at: Time.current) if token.oauth_client_id == client.id && !token.revoked?
    elsif (refresh = RefreshToken.authenticate(params[:token]))
      # リフレッシュトークンの失効はグラント全体の終了を意味するため、同じ
      # 認可コードから発行された全トークンを道連れにする(RFC 7009 §2.1 SHOULD)。
      refresh.authorization_code.revoke_issued_tokens! if refresh.oauth_client_id == client.id
    end

    head :ok
  end

  private

  # publicクライアントは提示できるクレデンシャルを持たない(RFC 7009 §2.1 が
  # 参照する RFC 6749 §2.3 はpublicクライアントに認証を要求しない)。client_id
  # の自己申告で十分: 下のトークン所有チェックが本人のトークン以外を守るし、
  # 失効の実行には生トークンの所持が前提なので、なりすましで失えるものがない。
  def resolve_client_or_public
    if params[:client_secret].blank? && basic_credentials.nil? && params[:client_assertion].blank?
      client = OauthClient.find_by(id: params[:client_id])
      return [@audited_client = client, nil] if client&.public_client?
    end

    resolve_client
  end
end
