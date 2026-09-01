# オーダー(ServiceRequest)の日付の意味を fhir-client 側で統一した(2026-09-01):
#   authoredOn         = オーダー登録日時
#   occurrenceDateTime = オーダー開始日(実施予定日)
# それより前のクライアントは処方・注射・細菌検査・古い検体検査で「検査日/注射日/処方日」を
# authoredOn にだけ入れ、occurrence を書いていなかった。新しいクライアントはカルテの
# タイムラインも部門一覧も occurrence で引くので、無いままだとこれらのオーダーが見えなくなる。
# ここで authoredOn を occurrenceDateTime に写す(旧クライアントでは両者が同じ日を表していた)。
#
# - ヘッダ(basedOn を持たない SR)だけが対象。明細はカードにも一覧にも直接出ない。
# - 手術は「日付未定」を occurrence 無しで表すので触らない。
# - authoredOn 自体は書き換えない(開発環境のシードは意図的に過去日を入れている)。
# - version_id / resource_versions は動かさない(既存の backfill と同じ、静かな正規化)。
# - 条件が「occurrence[x] を持たない行」なので、再実行しても二度目は 0 件(冪等)。
class BackfillServiceRequestOccurrenceFromAuthoredOn < ActiveRecord::Migration[7.0]
  # Table-scoped stub so the backfill survives future changes to the real
  # ServiceRequest model/class (e.g. new validations, callbacks).
  class MigrationServiceRequest < ActiveRecord::Base
    self.table_name = "service_requests"
  end

  ORDER_TYPE_SYSTEM = "http://fhir-client.local/CodeSystem/order-type".freeze
  SURGERY_CATEGORY = {
    category: [{ coding: [{ system: ORDER_TYPE_SYSTEM, code: "surgery" }] }],
  }.to_json.freeze

  def up
    # 無料枠は RAM 512MB なので、jsonb の content を抱え込みすぎないよう小さめのバッチで回す。
    MigrationServiceRequest
      .where(deleted: false)
      .where("content ? 'authoredOn'")
      .where.not("content ? 'basedOn'")
      .where("NOT (content ?| array['occurrenceDateTime', 'occurrencePeriod', 'occurrenceTiming'])")
      .where.not("content @> ?::jsonb", SURGERY_CATEGORY)
      .find_each(batch_size: 200) do |request|
        authored = request.content["authoredOn"]
        next if authored.blank?

        # 抽出列は authored_on と同じ :datetime 変換の結果なので、値をそのまま写せばよい。
        request.update_columns(
          content: request.content.merge("occurrenceDateTime" => authored),
          occurrence_date_time: request.authored_on,
        )
      end
  end

  def down
    # 写した値と手入力の値を区別できないので戻さない(列は 20260823000001 のもの)。
  end
end
