class CreateOrganizationIdentifiers < ActiveRecord::Migration[7.0]
  def change
    create_table :organization_identifiers do |t|
      t.string :organization_id, null: false
      t.string :system
      t.string :value, null: false

      t.timestamps
    end

    add_foreign_key :organization_identifiers, :organizations
    add_index :organization_identifiers, :organization_id
    add_index :organization_identifiers, [:system, :value]
    add_index :organization_identifiers, :value
  end
end
