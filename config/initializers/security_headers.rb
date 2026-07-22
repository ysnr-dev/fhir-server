# API-only サーバー向けのレスポンスヘッダー強化。JSON しか返さないため
# CSP は導入しない(HTMLを描画しないので意味を持たない)。
Rails.application.config.action_dispatch.default_headers.merge!(
  "X-Frame-Options" => "DENY",
  "Referrer-Policy" => "no-referrer",
  "Cross-Origin-Resource-Policy" => "same-origin"
)
