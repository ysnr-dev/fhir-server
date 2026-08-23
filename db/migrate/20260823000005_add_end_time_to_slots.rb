class AddEndTimeToSlots < ActiveRecord::Migration[7.0]
  # Table-scoped stub so the backfill never depends on the real Slot model.
  class MigrationSlot < ActiveRecord::Base
    self.table_name = "slots"
  end

  def up
    add_column :slots, :end_time, :datetime
    add_index :slots, :end_time

    MigrationSlot.reset_column_information
    backfill_end_time
  end

  def down
    remove_column :slots, :end_time
  end

  private

  # 無料枠は RAM 512MB なので、小さめのバッチで回す。
  def backfill_end_time
    MigrationSlot.where("content ? 'end'").find_each(batch_size: 200) do |slot|
      time = parse_time(slot.content["end"])
      slot.update_column(:end_time, time) if time
    end
  end

  def parse_time(value)
    return nil if value.blank?

    Time.iso8601(value)
  rescue ArgumentError, TypeError
    nil
  end
end
