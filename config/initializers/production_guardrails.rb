# 本番で危険な設定ミスを「静かに開いたサーバー」ではなく起動エラーにする。
# ここで落ちた場合はデプロイ環境の環境変数を直すこと。
if Rails.env.production?
  if ENV["FHIR_AUTH_ENABLED"] == "false" && ENV["FHIR_AUTH_ALLOW_DISABLED"] != "true"
    raise <<~MSG
      FHIR_AUTH_ENABLED=false in production: all patient data would be served
      unauthenticated. If this is a synthetic-data demo server, set
      FHIR_AUTH_ALLOW_DISABLED=true to acknowledge; otherwise remove the override.
    MSG
  end

  # 管理API(/admin/oauth_clients)はOAuthクライアントの発行・削除ができる。
  # 未設定は許容する(その場合APIは常に503で閉じている)が、設定するなら弱い
  # トークンは許さない。定数を参照するとautoloadの順序に依存するのでリテラル。
  admin_token = ENV["FHIR_ADMIN_TOKEN"].presence
  if admin_token && admin_token.bytesize < 32
    raise <<~MSG
      FHIR_ADMIN_TOKEN is shorter than 32 bytes. The admin API can register and
      delete OAuth clients, and it is protected by this single shared secret.
      Generate one with `openssl rand -hex 32`, or unset the variable to keep
      the admin API disabled.
    MSG
  end

  if ENV.fetch("FHIR_ALLOWED_HOSTS", "").split(",").map(&:strip).reject(&:empty?).empty?
    raise <<~MSG
      FHIR_ALLOWED_HOSTS is not set. An empty config.hosts disables Rails host
      authorization entirely, enabling Host-header attacks. Set it to a
      comma-separated list of the hostnames this server is reached as
      (e.g. FHIR_ALLOWED_HOSTS=fhir.example.com).
    MSG
  end
end
