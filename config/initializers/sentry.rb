# エラーモニタリング(Sentry)。SENTRY_DSN 未設定なら完全に無効。
#
# PHI(患者情報)対策: FHIRサーバーではリクエストボディにもクエリ文字列にも
# 患者データが含まれる(例: ?identifier=..., ?name=...)。イベントには
# 例外クラス・メッセージ・バックトレース・リクエストパスだけを残し、
# ボディ・クエリ・Cookie・ヘッダーの類は一切送らない。
if ENV["SENTRY_DSN"].present?
  Sentry.init do |config|
    config.dsn = ENV["SENTRY_DSN"]
    config.environment = ENV.fetch("SENTRY_ENVIRONMENT", Rails.env)

    config.send_default_pii = false
    config.max_request_body_size = :none
    config.breadcrumbs_logger = [:sentry_logger]

    config.before_send = lambda do |event, _hint|
      if event.request
        event.request.data = nil
        event.request.cookies = nil
        event.request.headers = {}
        event.request.query_string = nil
        # URLはクエリを落としてパスのみに
        event.request.url = event.request.url.to_s.split("?").first
      end
      event
    end
  end
end
