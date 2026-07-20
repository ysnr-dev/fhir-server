class CreatePractitionerRoles < ActiveRecord::Migration[7.0]
  def change
    create_table :practitioner_roles, id: :string do |t|
      t.integer :version_id, null: false, default: 1
      t.jsonb :content, null: false
      t.boolean :deleted, null: false, default: false
      t.datetime :last_updated, null: false

      # Search-optimized extracted fields
      t.boolean :active
      t.string :practitioner_reference
      t.string :organization_reference
      t.string :role_code
      t.string :specialty_code

      t.timestamps
    end

    add_index :practitioner_roles, :active
    add_index :practitioner_roles, :practitioner_reference
    add_index :practitioner_roles, :organization_reference
    add_index :practitioner_roles, :role_code
    add_index :practitioner_roles, :specialty_code
    add_index :practitioner_roles, :last_updated
    add_index :practitioner_roles, :deleted
    add_index :practitioner_roles, :content, using: :gin
  end
end
