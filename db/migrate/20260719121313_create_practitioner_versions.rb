class CreatePractitionerVersions < ActiveRecord::Migration[7.0]
  def change
    create_table :practitioner_versions do |t|
      t.string :practitioner_id, null: false
      t.integer :version_id, null: false
      t.jsonb :content, null: false
      t.boolean :deleted, null: false, default: false
      t.datetime :last_updated, null: false

      t.timestamps
    end

    # Explicit short name: default Rails-generated name exceeds Postgres' 63-char index name limit.
    add_index :practitioner_versions, [:practitioner_id, :version_id],
              unique: true, name: "index_practitioner_versions_on_request_and_version"
  end
end
