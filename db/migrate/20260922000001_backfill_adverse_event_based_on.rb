# 有害事象(category=adverse-event の Observation)が「原因となった治療」を指す場所を
# 変えた(2026-09-22)。それまでは化学療法専用で、適用ヘッダへの参照を
# `regimen-order` 拡張の中に持っていたため、
#   - 拡張の中の参照は検索できず、1 コースぶんを見るのに患者の有害事象を全部読むしかない
#   - 放射線治療など化学療法以外の治療に付けられない
# という制約があった。新しいクライアントは **標準の basedOn** に治療のヘッダを置き、
# 種別と名前の写しを `treatment-context` 拡張に持つ。ここで既存の記録に basedOn と
# treatment-context を足し、`Observation?based-on=` で引けるようにする。
#
# - `regimen-order` 拡張は**消さない**。移行中の古いクライアントがまだそれを読むため
#   (クライアントが記録を書き直すと、新しい形だけになる)。
# - version_id / resource_versions は動かさない(既存の backfill と同じ、静かな正規化)。
# - 条件が「basedOn を持たない行」なので、再実行しても二度目は 0 件(冪等)。
class BackfillAdverseEventBasedOn < ActiveRecord::Migration[7.0]
  # Table-scoped stub so the backfill survives future changes to the real
  # Observation model/class (e.g. new validations, callbacks).
  class MigrationObservation < ActiveRecord::Base
    self.table_name = "observations"
  end

  ADVERSE_EVENT_CATEGORY = {
    category: [{ coding: [{ code: "adverse-event" }] }],
  }.to_json.freeze

  REGIMEN_ORDER_EXT_URL = "http://fhir-client.local/StructureDefinition/regimen-order".freeze
  TREATMENT_CONTEXT_EXT_URL = "http://fhir-client.local/StructureDefinition/treatment-context".freeze

  def up
    MigrationObservation
      .where(deleted: false)
      .where("content @> ?::jsonb", ADVERSE_EVENT_CATEGORY)
      .where.not("content ? 'basedOn'")
      .find_each(batch_size: 200) do |observation|
        extensions = observation.content["extension"] || []
        legacy = extensions.find { |e| e["url"] == REGIMEN_ORDER_EXT_URL }
        next if legacy.nil?

        parts = legacy["extension"] || []
        reference = parts.find { |e| e["url"] == "regimen" }&.dig("valueReference", "reference")
        next if reference.blank?

        cycle = parts.find { |e| e["url"] == "cycle" }&.[]("valueInteger")
        name = parts.find { |e| e["url"] == "name" }&.[]("valueString")
        context = {
          "url" => TREATMENT_CONTEXT_EXT_URL,
          "extension" => [
            { "url" => "type", "valueCode" => "chemo-regimen" },
            ({ "url" => "name", "valueString" => name } if name.present?),
            ({ "url" => "cycle", "valueInteger" => cycle } unless cycle.nil?)
          ].compact
        }

        observation.update_columns(
          content: observation.content.merge(
            "basedOn" => [{ "reference" => reference }],
            "extension" => extensions + [context]
          )
        )
      end
  end

  def down
    # 足した参照と手で入れた参照を区別できないので戻さない。
  end
end
