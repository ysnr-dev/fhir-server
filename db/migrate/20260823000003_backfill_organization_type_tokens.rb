class BackfillOrganizationTypeTokens < ActiveRecord::Migration[7.0]
  # Table-scoped stubs so the backfill survives future changes to the real
  # models (and so it never depends on app code, which may have moved on by
  # the time this migration runs on an old database).
  class MigrationOrganization < ActiveRecord::Base
    self.table_name = "organizations"
  end

  class MigrationResourceToken < ActiveRecord::Base
    self.table_name = "resource_tokens"
  end

  # resource_tokens は書き込み時にしか埋まらないため、Organization に type の
  # token 抽出を足しても既存データには行が無く、`?type=dept` で引けない。
  # 本番(Render 無料枠)には Shell も cron も無く
  # `rake fhir:reindex_tokens` を流せないので、デプロイのたびに entrypoint が
  # 実行する db:prepare に載せて自動で再索引する。
  #
  # 対象は Organization の type 行だけなので、他の型のトークンには触れない。
  def up
    delete_existing_type_tokens

    now = Time.current
    # 無料枠は RAM 512MB なので、jsonb の content を抱え込みすぎないよう
    # 小さめのバッチで回す。
    MigrationOrganization.where("content ? 'type'").find_in_batches(batch_size: 200) do |batch|
      rows = batch.flat_map { |organization| token_rows(organization, now) }
      MigrationResourceToken.insert_all(rows) if rows.any?
    end
  end

  def down
    delete_existing_type_tokens
  end

  private

  # 先に消してから入れ直すので、rake タスクで再索引済みの環境(開発環境)で流しても
  # 行が重複しない。
  def delete_existing_type_tokens
    MigrationResourceToken.where(resource_type: "Organization", param_name: "type").delete_all
  end

  # Fhir::TokenExtractor の :codeable_concept_list と同じ結果(全 concept の全 coding、
  # code が空の行は捨て、空 system は nil に正規化)。
  def token_rows(organization, now)
    Array(organization.content["type"]).flat_map do |concept|
      next [] unless concept.is_a?(Hash)

      Array(concept["coding"]).filter_map do |coding|
        next unless coding.is_a?(Hash)

        code = coding["code"]
        next if code.blank?

        {
          resource_type: "Organization",
          resource_id: organization.id,
          param_name: "type",
          system: coding["system"].presence,
          code: code,
          created_at: now,
          updated_at: now
        }
      end
    end
  end
end
