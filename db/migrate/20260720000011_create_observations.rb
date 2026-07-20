class CreateObservations < ActiveRecord::Migration[7.0]
  def change
    create_table :observations, id: :string do |t|
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
      t.datetime :effective_time

      t.timestamps
    end

    add_index :observations, :status
    add_index :observations, :category_code
    add_index :observations, :code_value
    add_index :observations, :code_text
    add_index :observations, :subject_reference
    add_index :observations, :encounter_reference
    add_index :observations, :effective_time
    add_index :observations, :last_updated
    add_index :observations, :deleted
    add_index :observations, :content, using: :gin
  end
end
