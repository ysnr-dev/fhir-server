# Observation の date 検索に effectivePeriod.start(有害事象の発現日)を載せる。抽出列は書き込み時に
# しか埋まらないので、既存の期間つきの記録はここで content から起こす(本番には Shell が無い)。
class BackfillObservationEffectivePeriodStart < ActiveRecord::Migration[7.0]
  # Table-scoped stub so the backfill never depends on the real model.
  class MigrationObservation < ActiveRecord::Base
    self.table_name = "observations"
  end

  def up
    MigrationObservation
      .where(effective_time: nil)
      .where("content ? 'effectivePeriod'")
      .find_each(batch_size: 200) do |record|
        time = Fhir::FieldExtractor.datetime(record.content.dig("effectivePeriod", "start"))
        record.update_columns(effective_time: time) if time
      end
  end

  def down
    # 書き込み時の抽出と同じ値なので戻さない。
  end
end
