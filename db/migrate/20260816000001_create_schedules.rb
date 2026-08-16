class CreateSchedules < ActiveRecord::Migration[8.0]
  def change
    create_table :schedules, id: :string do |t|
      t.integer :version_id, null: false, default: 1
      t.jsonb :content, null: false
      t.boolean :deleted, null: false, default: false
      t.datetime :last_updated, null: false

      # Search-optimized extracted fields (match ExtractionDefinitions::Schedule::FIELDS).
      # Schedule.actor is 1..* and matched by jsonb containment, so it has no column.
      # serviceCategory / serviceType / specialty are 0..* CodeableConcept and live
      # only in resource_tokens (see SearchDefinitions::Schedule for why).
      t.boolean :active
      t.datetime :planning_horizon_start
      t.datetime :planning_horizon_end

      t.timestamps
    end

    add_index :schedules, :active
    add_index :schedules, :planning_horizon_start
    add_index :schedules, :planning_horizon_end
    add_index :schedules, :last_updated
    add_index :schedules, :deleted
    add_index :schedules, :content, using: :gin
  end
end
