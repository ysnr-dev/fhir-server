# レート制限・一時ban(rack-attack)。閾値はすべて環境変数で調整可能。
#
# カウンタは MemoryStore(プロセス内)なので Puma ワーカーごとに独立する。
# WEB_CONCURRENCY=N の場合、実効上限は最大N倍になる点に注意。スケールアウト
# するなら Rack::Attack.cache.store を Redis 等の共有ストアに差し替えること。
class Rack::Attack
  OAUTH_PATHS = ["/oauth/token", "/oauth/revoke"].freeze

  RATE_TOKEN_IP     = Integer(ENV.fetch("FHIR_RATE_TOKEN_IP", 10))      # /分
  RATE_TOKEN_CLIENT = Integer(ENV.fetch("FHIR_RATE_TOKEN_CLIENT", 30))  # /5分
  RATE_API_TOKEN    = Integer(ENV.fetch("FHIR_RATE_API_TOKEN", 300))    # /分
  RATE_API_IP       = Integer(ENV.fetch("FHIR_RATE_API_IP", 120))       # /分

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

  # --- FHIR API 全般 ---------------------------------------------------------
  throttle("api/token", limit: RATE_API_TOKEN, period: 1.minute) do |req|
    next if OAUTH_PATHS.include?(req.path) || req.path == "/up"

    auth = req.get_header("HTTP_AUTHORIZATION")
    # 生トークンをキャッシュキーに載せないようダイジェスト化
    Digest::SHA256.hexdigest(auth) if auth&.match?(/\ABearer /i)
  end

  throttle("api/ip", limit: RATE_API_IP, period: 1.minute) do |req|
    next if OAUTH_PATHS.include?(req.path) || req.path == "/up"

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
