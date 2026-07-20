class CreateImmunizations < ActiveRecord::Migration[7.0]
  def change
    create_table :immunizations, id: :string do |t|
      t.integer :version_id, null: false, default: 1
      t.jsonb :content, null: false
      t.boolean :deleted, null: false, default: false
      t.datetime :last_updated, null: false

      # Search-optimized extracted fields
      t.string :status
      t.string :vaccine_code
      t.string :vaccine_text
      t.string :patient_reference
      t.datetime :occurrence_time
      t.string :lot_number

      t.timestamps
    end

    add_index :immunizations, :status
    add_index :immunizations, :vaccine_code
    add_index :immunizations, :patient_reference
    add_index :immunizations, :occurrence_time
    add_index :immunizations, :lot_number
    add_index :immunizations, :last_updated
    add_index :immunizations, :deleted
    add_index :immunizations, :content, using: :gin
  end
end
