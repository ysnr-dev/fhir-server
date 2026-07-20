class CreateLocations < ActiveRecord::Migration[7.0]
  def change
    create_table :locations, id: :string do |t|
      t.integer :version_id, null: false, default: 1
      t.jsonb :content, null: false
      t.boolean :deleted, null: false, default: false
      t.datetime :last_updated, null: false

      # Search-optimized extracted fields
      t.string :status
      t.string :name
      t.string :address_text
      t.string :type_code
      t.string :organization_reference

      t.timestamps
    end

    add_index :locations, :status
    add_index :locations, :name
    add_index :locations, :address_text
    add_index :locations, :type_code
    add_index :locations, :organization_reference
    add_index :locations, :last_updated
    add_index :locations, :deleted
    add_index :locations, :content, using: :gin
  end
end
