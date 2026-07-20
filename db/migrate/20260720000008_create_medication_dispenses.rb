class CreateMedicationDispenses < ActiveRecord::Migration[7.0]
  def change
    create_table :medication_dispenses, id: :string do |t|
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
      t.datetime :when_handed_over

      t.timestamps
    end

    add_index :medication_dispenses, :status
    add_index :medication_dispenses, :subject_reference
    add_index :medication_dispenses, :medication_code
    add_index :medication_dispenses, :medication_text
    add_index :medication_dispenses, :context_reference
    add_index :medication_dispenses, :when_handed_over
    add_index :medication_dispenses, :last_updated
    add_index :medication_dispenses, :deleted
    add_index :medication_dispenses, :content, using: :gin
  end
end
