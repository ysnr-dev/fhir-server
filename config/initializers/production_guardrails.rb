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

  if ENV.fetch("FHIR_ALLOWED_HOSTS", "").split(",").map(&:strip).reject(&:empty?).empty?
    raise <<~MSG
      FHIR_ALLOWED_HOSTS is not set. An empty config.hosts disables Rails host
      authorization entirely, enabling Host-header attacks. Set it to a
      comma-separated list of the hostnames this server is reached as
      (e.g. FHIR_ALLOWED_HOSTS=fhir.example.com).
    MSG
  end
end
