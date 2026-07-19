class CreateOrganizationVersions < ActiveRecord::Migration[7.0]
  def change
    create_table :organization_versions do |t|
      t.string :organization_id, null: false
      t.integer :version_id, null: false
      t.jsonb :content, null: false
      t.boolean :deleted, null: false, default: false
      t.datetime :last_updated, null: false

      t.timestamps
    end

    # Explicit short name: default Rails-generated name exceeds Postgres' 63-char index name limit.
    add_index :organization_versions, [:organization_id, :version_id],
              unique: true, name: "index_organization_versions_on_request_and_version"
  end
end
