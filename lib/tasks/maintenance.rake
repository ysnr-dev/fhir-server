namespace :fhir do
  desc "期限切れのアクセストークンとクライアントアサーションJTIを削除する(日次cron想定)"
  task purge_expired: :environment do
    # 期限切れ直後のトークンは監査調査(AuditEventのclient紐付け確認等)の
    # ため一定期間残す。保持期間は FHIR_TOKEN_RETENTION_DAYS(デフォルト30日)。
    retention_days = Integer(ENV.fetch("FHIR_TOKEN_RETENTION_DAYS", 30))
    tokens = AccessToken.where("expires_at < ?", retention_days.days.ago).delete_all
    refresh_tokens = RefreshToken.where("expires_at < ?", retention_days.days.ago).delete_all
    jtis = ClientAssertionJti.where("expires_at < ?", Time.current).delete_all

    puts "purged #{tokens} access token(s) expired more than #{retention_days} days ago"
    puts "purged #{refresh_tokens} refresh token(s) expired more than #{retention_days} days ago"
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

  desc "過ぎた予約枠(Slot)を物理削除する(日次cron想定)"
  task purge_past_slots: :environment do
    # 予約枠は 15 分刻みなどで機械的に大量生成されるため、放っておくと過去ぶんが
    # 積み上がる。過ぎた枠は使い道が無いので、保持期間を過ぎたら物理削除して減らす。
    # 保持期間は SLOT_RETENTION_DAYS(デフォルト30日)。
    retention_days = Integer(ENV.fetch("SLOT_RETENTION_DAYS", 30))
    cutoff = retention_days.days.ago

    # 予約が押さえている枠(busy / busy-tentative)は消さない。予約の取消・日時変更は
    # 枠の現物を読んでから status を戻すので、消すとそれらの操作が 410 で失敗する。
    # 論理削除済み(deleted)の枠はもう読めないので、状態によらず物理削除の対象。
    past = Slot.where(start_time: ...cutoff)
    scope = past.where(status: %w[free busy-unavailable entered-in-error]).or(past.where(deleted: true))

    # dependent: :destroy に任せて resource_versions / resource_tokens /
    # resource_identifiers も一緒に消す(履歴ごと消すのが目的なので delete_all は使わない)。
    # 一度に抱え込まないようバッチで回す。
    purged = 0
    scope.find_in_batches(batch_size: 500) do |batch|
      batch.each(&:destroy)
      purged += batch.size
    end

    puts "purged #{purged} slot(s) starting more than #{retention_days} days ago (kept booked ones)"
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

  desc "resource_identifiers を content から再構築する(extra_identifiers の宣言追加時に一度実行)"
  task reindex_identifiers: :environment do
    # resource_identifiers は書き込み時にしか埋まらないため、識別子の追加取り込み
    # 箇所(例: Practitioner.qualification[].identifier)を宣言した後、既存リソースは
    # 再同期するまで新しい場所の identifier で検索できない。extra_identifiers を持つ
    # 型だけ走査すれば十分(RESOURCE_TYPE で単一型に限定も可)。
    types = ENV["RESOURCE_TYPE"].presence&.split(",") ||
            Fhir::ResourceRegistry.types.select { |t| Fhir::ResourceRegistry.entry_for(t)[:extra_identifiers].present? }
    total = 0
    types.each do |type|
      model = Fhir::ResourceRegistry.entry_for(type).fetch(:model)
      count = 0
      model.find_each do |record|
        record.sync_identifiers!
        count += 1
      end
      total += count
      puts "reindexed #{count} #{type} record(s)"
    end
    puts "done: reindexed identifiers for #{total} record(s) across #{types.size} type(s)"
  end
end
