class CreateMedicationStatements < ActiveRecord::Migration[7.0]
  def change
    create_table :medication_statements, id: :string do |t|
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
      t.datetime :effective_time

      t.timestamps
    end

    add_index :medication_statements, :status
    add_index :medication_statements, :subject_reference
    add_index :medication_statements, :medication_code
    add_index :medication_statements, :medication_text
    add_index :medication_statements, :context_reference
    add_index :medication_statements, :effective_time
    add_index :medication_statements, :last_updated
    add_index :medication_statements, :deleted
    add_index :medication_statements, :content, using: :gin
  end
end
