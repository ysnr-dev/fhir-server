class CreateOrganizations < ActiveRecord::Migration[7.0]
  def change
    create_table :organizations, id: :string do |t|
      t.integer :version_id, null: false, default: 1
      t.jsonb :content, null: false
      t.boolean :deleted, null: false, default: false
      t.datetime :last_updated, null: false

      # Search-optimized extracted fields
      t.boolean :active
      t.string :name

      t.timestamps
    end

    add_index :organizations, :name
    add_index :organizations, :active
    add_index :organizations, :last_updated
    add_index :organizations, :deleted
    add_index :organizations, :content, using: :gin
  end
end
