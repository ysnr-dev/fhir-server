# レート制限・一時ban(rack-attack)。閾値はすべて環境変数で調整可能。
#
# カウンタは MemoryStore(プロセス内)なので Puma ワーカーごとに独立する。
# WEB_CONCURRENCY=N の場合、実効上限は最大N倍になる点に注意。スケールアウト
# するなら Rack::Attack.cache.store を Redis 等の共有ストアに差し替えること。
class Rack::Attack
  OAUTH_PATHS = ["/oauth/token", "/oauth/revoke"].freeze
  # 対話型launchのブラウザ3画面。ログインフォームを晒すため、APIとは別枠で
  # 制限する(Bearerを持たないのでapi/ipに巻き込むと人間の操作を阻害する)。
  BROWSER_OAUTH_PATHS = ["/oauth/authorize", "/oauth/login", "/oauth/consent"].freeze
  # 管理API。/admin/oauth_clients/:id のようにパスが可変なので、他と違って
  # 完全一致の定数では書けない(admin_path? を使う)。
  ADMIN_PATH_PREFIX = "/admin/".freeze
  # EHR launch の発行はカルテの操作ごとに飛ぶ(1 画面 1 回)。管理トークンの
  # ブルートフォース対策の枠に入れると起動回数の上限になるので別枠にする。
  LAUNCH_ADMIN_PATH = "/admin/launch_contexts".freeze

  RATE_TOKEN_IP     = Integer(ENV.fetch("FHIR_RATE_TOKEN_IP", 10))      # /分
  RATE_TOKEN_CLIENT = Integer(ENV.fetch("FHIR_RATE_TOKEN_CLIENT", 30))  # /5分
  RATE_API_TOKEN    = Integer(ENV.fetch("FHIR_RATE_API_TOKEN", 300))    # /分
  RATE_API_IP       = Integer(ENV.fetch("FHIR_RATE_API_IP", 120))       # /分
  RATE_AUTHORIZE_IP = Integer(ENV.fetch("FHIR_RATE_AUTHORIZE_IP", 30))  # /分
  RATE_LOGIN_IP     = Integer(ENV.fetch("FHIR_RATE_LOGIN_IP", 10))      # /分
  RATE_ADMIN_IP     = Integer(ENV.fetch("FHIR_RATE_ADMIN_IP", 30))      # /分
  RATE_LAUNCH_IP    = Integer(ENV.fetch("FHIR_RATE_LAUNCH_IP", 120))    # /分
  RATE_LAUNCH_CLIENT = Integer(ENV.fetch("FHIR_RATE_LAUNCH_CLIENT", 120)) # /分

  def self.admin_path?(req)
    req.path.start_with?(ADMIN_PATH_PREFIX)
  end

  # EHR launch の authorize(launch パラメータ付き GET)。病院の NAT では全医療者が
  # 同一 IP になるため、ログイン画面を晒す standalone とは別にクライアント単位で数える。
  def self.ehr_launch_request?(req)
    req.get? && req.path == "/oauth/authorize" && req.GET["launch"].present?
  end

  self.cache.store = ActiveSupport::Cache::MemoryStore.new

  # テストではデフォルト無効(rack_attack_spec が個別に有効化する)
  self.enabled = !Rails.env.test?

  safelist("health-check") { |req| req.path == "/up" }

  # --- 任意のB2B向けIP許可リスト --------------------------------------------
  # FHIR_IP_ALLOWLIST(CIDRカンマ区切り)を設定した場合のみ、リスト外IPを
  # /up 以外すべて403にする。未設定なら制限なし。
  ip_allowlist = ENV.fetch("FHIR_IP_ALLOWLIST", "").split(",").map(&:strip).reject(&:empty?).map { |cidr| IPAddr.new(cidr) }
  if ip_allowlist.any?
    blocklist("outside-ip-allowlist") do |req|
      req.path != "/up" && ip_allowlist.none? do |cidr|
        cidr.include?(req.ip)
      rescue IPAddr::Error
        false
      end
    end
  end

  # --- 認証失敗の連発ban(Fhir::AuthThrottle が401時に記録) ----------------
  blocklist("auth-failure-ban") do |req|
    req.path != "/up" && Fhir::AuthThrottle.banned?(req.ip)
  end

  # --- OAuthエンドポイント(認証前に叩ける = ブルートフォースの入口) --------
  throttle("oauth/ip", limit: RATE_TOKEN_IP, period: 1.minute) do |req|
    req.ip if req.post? && OAUTH_PATHS.include?(req.path)
  end

  throttle("oauth/client", limit: RATE_TOKEN_CLIENT, period: 5.minutes) do |req|
    client_id_hint(req) if req.post? && OAUTH_PATHS.include?(req.path)
  end

  # --- 対話型launchのブラウザ画面 --------------------------------------------
  throttle("oauth-browser/ip", limit: RATE_AUTHORIZE_IP, period: 1.minute) do |req|
    req.ip if BROWSER_OAUTH_PATHS.include?(req.path) && !ehr_launch_request?(req)
  end

  throttle("oauth-launch/client", limit: RATE_LAUNCH_CLIENT, period: 1.minute) do |req|
    "launch:#{req.GET['client_id']}" if ehr_launch_request?(req)
  end

  # ログイン試行はさらに厳しく。失敗は Fhir::AuthThrottle 経由で
  # auth-failure-ban にも積まれるので、二段構えになる。
  throttle("oauth-login/ip", limit: RATE_LOGIN_IP, period: 1.minute) do |req|
    req.ip if req.post? && req.path == "/oauth/login"
  end

  # --- 管理API ---------------------------------------------------------------
  # 管理APIの401は auth-failure-ban に積まない(呼び出し元は単一IPの中継サーバー
  # なので、積むと管理トークンの打ち間違いでFHIR API全体が遮断される)。
  # 共有トークンへのブルートフォースはこのスロットルだけが止める。
  throttle("admin/ip", limit: RATE_ADMIN_IP, period: 1.minute) do |req|
    req.ip if admin_path?(req) && req.path != LAUNCH_ADMIN_PATH
  end

  throttle("admin-launch/ip", limit: RATE_LAUNCH_IP, period: 1.minute) do |req|
    req.ip if req.path == LAUNCH_ADMIN_PATH
  end

  # --- FHIR API 全般 ---------------------------------------------------------
  throttle("api/token", limit: RATE_API_TOKEN, period: 1.minute) do |req|
    next if admin_path?(req)
    next if OAUTH_PATHS.include?(req.path) || BROWSER_OAUTH_PATHS.include?(req.path) || req.path == "/up"

    auth = req.get_header("HTTP_AUTHORIZATION")
    # 生トークンをキャッシュキーに載せないようダイジェスト化
    Digest::SHA256.hexdigest(auth) if auth&.match?(/\ABearer /i)
  end

  throttle("api/ip", limit: RATE_API_IP, period: 1.minute) do |req|
    next if admin_path?(req)
    next if OAUTH_PATHS.include?(req.path) || BROWSER_OAUTH_PATHS.include?(req.path) || req.path == "/up"

    auth = req.get_header("HTTP_AUTHORIZATION")
    req.ip unless auth&.match?(/\ABearer /i)
  end

  # クライアント単位スロットルの識別子。Basicヘッダー、フォームパラメータ、
  # または client_assertion の未検証 iss クレームから取り出す。認証には一切
  # 使わない(スロットルキーの粒度を上げるためのヒントに過ぎない)。
  def self.client_id_hint(req)
    auth = req.get_header("HTTP_AUTHORIZATION")
    if auth&.match?(/\ABasic /i)
      decoded = Base64.decode64(auth.split(" ", 2).last.to_s)
      id = decoded.split(":", 2).first
      return "basic:#{id}" if id.present?
    end

    form = begin
      req.POST
    rescue StandardError
      {}
    end
    return "post:#{form['client_id']}" if form["client_id"].present?

    assertion = form["client_assertion"].to_s
    payload = assertion.split(".")[1]
    if payload
      iss = begin
        JSON.parse(Base64.urlsafe_decode64(payload + "=" * (-payload.length % 4)))["iss"]
      rescue StandardError
        nil
      end
      return "jwt:#{iss}" if iss.present?
    end

    # 識別子が取れないリクエストはIPでまとめる
    "anon:#{req.ip}"
  end

  self.throttled_responder = lambda do |req|
    period = (req.env["rack.attack.match_data"] || {})[:period].to_i
    body = Fhir::OperationOutcome.single(
      severity: "error", code: "throttled",
      diagnostics: "Rate limit exceeded; retry after #{period} seconds"
    ).to_json
    [429, { "content-type" => "application/fhir+json", "retry-after" => period.to_s }, [body]]
  end

  self.blocklisted_responder = lambda do |_req|
    body = Fhir::OperationOutcome.single(
      severity: "error", code: "security", diagnostics: "Request blocked"
    ).to_json
    [403, { "content-type" => "application/fhir+json" }, [body]]
  end
end
