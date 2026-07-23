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

  desc "スタックしたBulk Data $exportを失敗扱いにし、期限切れのエクスポートを削除する(日次cron想定)"
  task purge_bulk_exports: :environment do
    # dynoの再起動でジョブが失われると in_progress のまま残るため、ハートビート
    # (updated_at)が古いものはここで確実に failed に倒す(pollerを永遠に202で
    # 待たせない)。保持期間は BULK_EXPORT_RETENTION_DAYS(デフォルト3日、Neon無料枠の
    # ストレージを圧迫しないよう短め)。
    retention_days = Integer(ENV.fetch("BULK_EXPORT_RETENTION_DAYS", 3))

    stale = BulkExport.where(status: "in_progress").select(&:stale?)
    stale.each(&:mark_stale_failed!)

    expired = BulkExport.where(status: %w[completed failed cancelled]).where("created_at < ?", retention_days.days.ago)
    expired_count = expired.count
    expired.destroy_all

    puts "marked #{stale.size} stale in-progress export(s) as failed"
    puts "purged #{expired_count} export(s) finished more than #{retention_days} days ago"
  end

  desc "resource_tokens を content から再構築する(system|code token 検索の導入時に一度実行)"
  task reindex_tokens: :environment do
    # resource_tokens は書き込み時にしか埋まらないため、テーブル導入前から存在する
    # リソースには token 行が無い。全リソースを走査して sync_tokens! を呼び直す。
    total = 0
    Fhir::ResourceRegistry.types.each do |type|
      model = Fhir::ResourceRegistry.entry_for(type).fetch(:model)
      count = 0
      model.find_each do |record|
        record.sync_tokens!
        count += 1
      end
      total += count
      puts "reindexed #{count} #{type} record(s)"
    end
    puts "done: reindexed tokens for #{total} record(s) across #{Fhir::ResourceRegistry.types.size} types"
  end
end
