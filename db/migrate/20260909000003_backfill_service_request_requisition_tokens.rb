class BackfillServiceRequestRequisitionTokens < ActiveRecord::Migration[7.0]
  # Table-scoped stubs so the backfill never depends on app code.
  class MigrationServiceRequest < ActiveRecord::Base
    self.table_name = "service_requests"
  end

  class MigrationResourceToken < ActiveRecord::Base
    self.table_name = "resource_tokens"
  end

  # resource_tokens は書き込み時にしか埋まらないため、ServiceRequest に requisition の
  # token 抽出を足しても既存データには行が無く、`?requisition=` で引けない
  # (レジメンの日オーダー・オーダーセットの適用が対象)。本番には Shell も cron も無く
  # `rake fhir:reindex_tokens` を流せないので、db:prepare に載せて自動で再索引する。
  # 対象は ServiceRequest の requisition 行だけ。
  def up
    delete_existing_requisition_tokens

    now = Time.current
    # 無料枠は RAM 512MB なので、小さめのバッチで回す。
    MigrationServiceRequest.where("content ? 'requisition'").find_in_batches(batch_size: 200) do |batch|
      rows = batch.filter_map { |request| token_row(request, now) }
      MigrationResourceToken.insert_all(rows) if rows.any?
    end
  end

  def down
    delete_existing_requisition_tokens
  end

  private

  def delete_existing_requisition_tokens
    MigrationResourceToken.where(resource_type: "ServiceRequest", param_name: "requisition").delete_all
  end

  # Fhir::TokenExtractor の :identifier と同じ結果(system|value を 1 行、value が空なら無し、
  # 空 system は nil に正規化)。
  def token_row(request, now)
    identifier = request.content["requisition"]
    return nil unless identifier.is_a?(Hash)

    value = identifier["value"]
    return nil if value.blank?

    {
      resource_type: "ServiceRequest",
      resource_id: request.id,
      param_name: "requisition",
      system: identifier["system"].presence,
      code: value,
      created_at: now,
      updated_at: now
    }
  end
end
