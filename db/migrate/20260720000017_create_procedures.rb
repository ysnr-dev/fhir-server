class CreateProcedures < ActiveRecord::Migration[7.0]
  def change
    create_table :procedures, id: :string do |t|
      t.integer :version_id, null: false, default: 1
      t.jsonb :content, null: false
      t.boolean :deleted, null: false, default: false
      t.datetime :last_updated, null: false

      # Search-optimized extracted fields
      t.string :status
      t.string :category_code
      t.string :code_value
      t.string :code_text
      t.string :subject_reference
      t.string :encounter_reference
      t.datetime :performed_time

      t.timestamps
    end

    add_index :procedures, :status
    add_index :procedures, :category_code
    add_index :procedures, :code_value
    add_index :procedures, :subject_reference
    add_index :procedures, :encounter_reference
    add_index :procedures, :performed_time
    add_index :procedures, :last_updated
    add_index :procedures, :deleted
    add_index :procedures, :content, using: :gin
  end
end
