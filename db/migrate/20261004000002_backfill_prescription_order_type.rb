# fhir-client の処方オーダー(ヘッダ ServiceRequest)は、ほかの部門オーダーと同じく
# category にオーダー種別 `order-type|prescription` を持つ(2026-10-04)。それより前の
# クライアントは処方にだけ種別を付けず「種別が無い ServiceRequest が処方」としていたので、
# 既存の処方ヘッダに種別を足し、`category=order-type|prescription` で引けるようにする。
#
# - 対象は処方区分(prescription-category)を持ち、order-type を持たないヘッダ
#   (basedOn を持たない SR)。処方区分は処方だけが持つ CodeSystem。
# - 種別は category の先頭に置く(ほかの種別と同じ並び)。
# - resource_tokens にも category の行を足す(token は書き込み時にしか埋まらない)。
# - version_id / resource_versions は動かさない(既存の backfill と同じ、静かな正規化)。
# - 条件が「order-type を持たない行」なので、再実行しても二度目は 0 件(冪等)。
class BackfillPrescriptionOrderType < ActiveRecord::Migration[7.0]
  # Table-scoped stubs so the backfill never depends on app code.
  class MigrationServiceRequest < ActiveRecord::Base
    self.table_name = "service_requests"
  end

  class MigrationResourceToken < ActiveRecord::Base
    self.table_name = "resource_tokens"
  end

  ORDER_TYPE_SYSTEM = "http://fhir-client.local/CodeSystem/order-type".freeze
  PRESCRIPTION_CATEGORY_SYSTEM = "http://fhir-client.local/CodeSystem/prescription-category".freeze
  PRESCRIPTION_CODE = "prescription".freeze

  HAS_PRESCRIPTION_CATEGORY = {
    category: [{ coding: [{ system: PRESCRIPTION_CATEGORY_SYSTEM }] }],
  }.to_json.freeze
  HAS_ORDER_TYPE = {
    category: [{ coding: [{ system: ORDER_TYPE_SYSTEM }] }],
  }.to_json.freeze

  def up
    now = Time.current
    # 無料枠は RAM 512MB なので、jsonb の content を抱え込みすぎないよう小さめのバッチで回す。
    MigrationServiceRequest
      .where(deleted: false)
      .where.not("content ? 'basedOn'")
      .where("content @> ?::jsonb", HAS_PRESCRIPTION_CATEGORY)
      .where.not("content @> ?::jsonb", HAS_ORDER_TYPE)
      .find_in_batches(batch_size: 200) do |batch|
        batch.each do |request|
          order_type = { "coding" => [{ "system" => ORDER_TYPE_SYSTEM, "code" => PRESCRIPTION_CODE, "display" => "処方" }] }
          request.update_columns(
            content: request.content.merge("category" => [order_type, *Array(request.content["category"])]),
          )
        end
        MigrationResourceToken.insert_all(batch.map do |request|
          {
            resource_type: "ServiceRequest",
            resource_id: request.id,
            param_name: "category",
            system: ORDER_TYPE_SYSTEM,
            code: PRESCRIPTION_CODE,
            created_at: now,
            updated_at: now,
          }
        end)
      end
  end

  def down
    # 足した種別と新しいクライアントが書いた種別を区別できないので戻さない。
  end
end
