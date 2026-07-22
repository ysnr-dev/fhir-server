namespace :fhir do
  desc "期限切れのアクセストークンとクライアントアサーションJTIを削除する(日次cron想定)"
  task purge_expired: :environment do
    # 期限切れ直後のトークンは監査調査(AuditEventのclient紐付け確認等)の
    # ため一定期間残す。保持期間は FHIR_TOKEN_RETENTION_DAYS(デフォルト30日)。
    retention_days = Integer(ENV.fetch("FHIR_TOKEN_RETENTION_DAYS", 30))
    tokens = AccessToken.where("expires_at < ?", retention_days.days.ago).delete_all
    jtis = ClientAssertionJti.where("expires_at < ?", Time.current).delete_all

    puts "purged #{tokens} access token(s) expired more than #{retention_days} days ago"
    puts "purged #{jtis} expired client assertion jti(s)"
  end
end
