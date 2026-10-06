# Observation を数値の測定値(value-quantity)で検索できるようにする。抽出列は書き込み時に
# しか埋まらないので、既存の測定値はここで content から起こす(本番には Shell が無い)。
class AddValueQuantityToObservations < ActiveRecord::Migration[7.0]
  # Table-scoped stub so the backfill never depends on the real model.
  class MigrationObservation < ActiveRecord::Base
    self.table_name = "observations"
  end

  def up
    add_column :observations, :value_quantity, :decimal
    add_index :observations, :value_quantity

    MigrationObservation.reset_column_information
    backfill
  end

  def down
    remove_index :observations, :value_quantity
    remove_column :observations, :value_quantity
  end

  private

  # 無料枠は RAM 512MB なので、小さめのバッチで回す。
  def backfill
    MigrationObservation
      .where("content ? 'valueQuantity'")
      .find_each(batch_size: 200) do |record|
        value = decimal(record.content.dig("valueQuantity", "value"))
        record.update_columns(value_quantity: value) if value
      end
  end

  # Fhir::FieldExtractor.decimal と同じ規則。
  def decimal(value)
    case value
    when Numeric then BigDecimal(value.to_s)
    when String then value.match?(/\A-?\d+(\.\d+)?\z/) ? BigDecimal(value) : nil
    end
  end
end
