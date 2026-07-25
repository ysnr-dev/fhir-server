module Fhir
  # 管理API(/admin/*)専用の共有トークン認証。
  #
  # FHIRのスコープ体系とは完全に独立させている。OAuthクライアントの登録・削除は
  # patient/ でも system/ でもない特権で、既存のスコープに載せると
  # 「system/*.* を持つクライアントが自分の権限を作り直せる」ことになる。
  #
  # Fhir::Auth.enabled? も一切参照しない。認証OFFの開発サーバー(既定)でも
  # 管理APIは閉じたままにする -- ここが「開いていた」ときの被害は
  # FHIRデータの閲覧ではなく、資格情報の発行そのものになるため。
  module AdminAuth
    # 32バイト = openssl rand -hex 32 の出力長。これ未満は本番で起動を止める
    # (config/initializers/production_guardrails.rb)。
    MIN_TOKEN_BYTES = 32

    module_function

    def token
      ENV["FHIR_ADMIN_TOKEN"].presence
    end

    # 未設定なら管理APIは「無効」。呼ばれても常に503を返す(fail closed)。
    def enabled?
      token.present?
    end

    def valid?(presented)
      expected = token
      return false if expected.blank? || presented.blank?

      # secure_compare は内部でSHA256にしてから固定長比較するので、
      # 長さの異なるトークンでもタイミング差を漏らさない。
      ActiveSupport::SecurityUtils.secure_compare(presented.to_s, expected)
    end
  end
end
