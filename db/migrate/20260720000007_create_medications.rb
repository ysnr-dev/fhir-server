class CreateMedications < ActiveRecord::Migration[7.0]
  def change
    create_table :medications, id: :string do |t|
      t.integer :version_id, null: false, default: 1
      t.jsonb :content, null: false
      t.boolean :deleted, null: false, default: false
      t.datetime :last_updated, null: false

      # Search-optimized extracted fields
      t.string :status
      t.string :medication_code
      t.string :medication_text
      t.string :form_code
      t.string :manufacturer_reference

      t.timestamps
    end

    add_index :medications, :status
    add_index :medications, :medication_code
    add_index :medications, :medication_text
    add_index :medications, :form_code
    add_index :medications, :manufacturer_reference
    add_index :medications, :last_updated
    add_index :medications, :deleted
    add_index :medications, :content, using: :gin
  end
end
