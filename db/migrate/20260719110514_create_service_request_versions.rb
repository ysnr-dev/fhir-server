class CreateServiceRequestVersions < ActiveRecord::Migration[7.0]
  def change
    create_table :service_request_versions do |t|
      t.string :service_request_id, null: false
      t.integer :version_id, null: false
      t.jsonb :content, null: false
      t.boolean :deleted, null: false, default: false
      t.datetime :last_updated, null: false

      t.timestamps
    end

    # Explicit short name: default Rails-generated name exceeds Postgres' 63-char index name limit.
    add_index :service_request_versions, [:service_request_id, :version_id],
              unique: true, name: "index_service_request_versions_on_request_and_version"
  end
end
