# Procedure.performed[x] を期間として索引する。これまで performedDateTime しか索引せず、
# 手術の実施記録(performedPeriod)は `date` で絞れなかった。
#   performedDateTime  -> performed_time = performed_end = その時刻(点)
#   performedPeriod    -> performed_time = start、performed_end = end(進行中なら nil)
class AddPerformedEndToProcedures < ActiveRecord::Migration[7.0]
  # Table-scoped stub so the backfill never depends on the real Procedure model.
  class MigrationProcedure < ActiveRecord::Base
    self.table_name = "procedures"
  end

  def up
    add_column :procedures, :performed_end, :datetime
    add_index :procedures, :performed_end

    MigrationProcedure.reset_column_information
    backfill_performed
  end

  def down
    remove_column :procedures, :performed_end
  end

  private

  # 無料枠は RAM 512MB なので、小さめのバッチで回す。
  def backfill_performed
    # 点の実施記録: 終了 = 開始。抽出列の値をそのまま写す。
    MigrationProcedure
      .where("content ? 'performedDateTime'")
      .where.not(performed_time: nil)
      .in_batches(of: 500)
      .update_all("performed_end = performed_time")

    # 期間の実施記録: 開始・終了を content から起こす(開始はこれまで索引されていなかった)。
    MigrationProcedure
      .where("content ? 'performedPeriod'")
      .find_each(batch_size: 200) do |procedure|
        period = procedure.content["performedPeriod"]
        next unless period.is_a?(Hash)

        procedure.update_columns(
          performed_time: parse_time(period["start"]),
          performed_end: parse_time(period["end"])
        )
      end
  end

  # Fhir::FieldExtractor.datetime と同じ規則: 日付だけの値は UTC 0 時として持つ。
  def parse_time(value)
    return nil if value.blank?

    Time.iso8601(value)
  rescue ArgumentError, TypeError
    begin
      Date.iso8601(value).to_time(:utc)
    rescue ArgumentError, TypeError
      nil
    end
  end
end
