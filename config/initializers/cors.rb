# CORS は Bearer トークンだけで守られるパスに限って全オリジンに開く。
#
# 対象はブラウザ上で動く SMART アプリ(EHR launch の public client)が直接呼ぶもの:
# トークン交換・失効・discovery・FHIR API。Cookie は一切使わない(credentials: false)
# ので、オリジンを許可リストにしても守れるものは増えず、public client のアプリは
# 任意のオリジンにあり得るため "*" にする。
#
# Cookie を使う /oauth/authorize|login|consent、管理 API、クライアント認証が要る
# /oauth/introspect は対象外(ブラウザから叩く想定が無い)。Cross-Origin-Resource-Policy
# は CORS モードの fetch には効かないので security_headers.rb のまま。
#
# rack-attack より前(先頭)に置く: preflight(Authorization 無しの OPTIONS)を
# api/ip の回数に数えない。
Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins "*"

    resource "/oauth/token", headers: :any, methods: %i[post options], credentials: false
    resource "/oauth/revoke", headers: :any, methods: %i[post options], credentials: false
    resource "/.well-known/*", headers: :any, methods: %i[get options], credentials: false
    resource "/metadata", headers: :any, methods: %i[get options], credentials: false

    # FHIR API(transaction の POST / を含む)。/oauth/ と /admin/ と /up は除く。
    resource "/", headers: :any, methods: %i[post options], credentials: false
    resource %r{\A/(?!oauth/|admin/|up\z|\.well-known/)[^/]+(/.*)?\z},
             headers: :any,
             methods: %i[get post put patch delete options],
             expose: %w[ETag Location Content-Location WWW-Authenticate Retry-After],
             max_age: 600,
             credentials: false
  end
end
