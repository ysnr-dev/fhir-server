class CreateMedicationAdministrations < ActiveRecord::Migration[7.0]
  def change
    create_table :medication_administrations, id: :string do |t|
      t.integer :version_id, null: false, default: 1
      t.jsonb :content, null: false
      t.boolean :deleted, null: false, default: false
      t.datetime :last_updated, null: false

      # Search-optimized extracted fields
      t.string :status
      t.string :subject_reference
      t.string :medication_code
      t.string :medication_text
      t.string :context_reference
      t.string :request_reference
      t.datetime :effective_time

      t.timestamps
    end

    add_index :medication_administrations, :status
    add_index :medication_administrations, :subject_reference
    add_index :medication_administrations, :medication_code
    add_index :medication_administrations, :medication_text
    add_index :medication_administrations, :context_reference
    add_index :medication_administrations, :request_reference
    add_index :medication_administrations, :effective_time
    add_index :medication_administrations, :last_updated
    add_index :medication_administrations, :deleted
    add_index :medication_administrations, :content, using: :gin
  end
end
