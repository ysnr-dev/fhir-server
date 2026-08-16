class CreateSlots < ActiveRecord::Migration[8.0]
  def change
    create_table :slots, id: :string do |t|
      t.integer :version_id, null: false, default: 1
      t.jsonb :content, null: false
      t.boolean :deleted, null: false, default: false
      t.datetime :last_updated, null: false

      # Search-optimized extracted fields (match ExtractionDefinitions::Slot::FIELDS).
      # `start` is a SQL reserved word, so the column is start_time; R4 defines no
      # `end` search parameter on Slot, so Slot.end stays in content only.
      # serviceCategory / serviceType / specialty are 0..* CodeableConcept and live
      # only in resource_tokens (see SearchDefinitions::Slot for why).
      t.string :status
      t.string :appointment_type
      t.string :schedule_reference
      t.datetime :start_time

      t.timestamps
    end

    add_index :slots, :status
    add_index :slots, :appointment_type
    add_index :slots, :schedule_reference
    add_index :slots, :start_time
    add_index :slots, :last_updated
    add_index :slots, :deleted
    add_index :slots, :content, using: :gin
  end
end
