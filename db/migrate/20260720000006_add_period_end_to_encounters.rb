class AddPeriodEndToEncounters < ActiveRecord::Migration[7.0]
  # Table-scoped stub so the backfill survives future changes to the real
  # Encounter model/class (e.g. new validations, callbacks).
  class MigrationEncounter < ActiveRecord::Base
    self.table_name = "encounters"
  end

  def up
    add_column :encounters, :period_end, :datetime
    add_index :encounters, :period_end

    MigrationEncounter.reset_column_information
    backfill_period_end
  end

  def down
    remove_column :encounters, :period_end
  end

  private

  def backfill_period_end
    MigrationEncounter.where("content -> 'period' ? 'end'").find_each do |encounter|
      time = parse_time(encounter.content.dig("period", "end"))
      encounter.update_column(:period_end, time) if time
    end
  end

  def parse_time(value)
    return nil if value.blank?

    Time.iso8601(value)
  rescue ArgumentError, TypeError
    nil
  end
end
