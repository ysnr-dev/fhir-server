class ConsolidateResourceVersionsAndIdentifiers < ActiveRecord::Migration[7.0]
  def up
    create_table :resource_versions do |t|
      t.string   :resource_type, null: false
      t.string   :resource_id,   null: false
      t.integer  :version_id,    null: false
      t.jsonb    :content,       null: false
      t.boolean  :deleted,       null: false, default: false
      t.datetime :last_updated,  null: false
      t.timestamps
      t.index %i[resource_type resource_id version_id],
              unique: true, name: "index_resource_versions_on_type_id_version"
    end

    create_table :resource_identifiers do |t|
      t.string :resource_type, null: false
      t.string :resource_id,   null: false
      t.string :system
      t.string :value,         null: false
      t.timestamps
      t.index %i[resource_type resource_id]
      t.index %i[system value]
      t.index :value
    end

    # Fresh dev-only data; no backfill from the old per-resource tables.
    %i[patient practitioner organization medication_request service_request].each do |resource|
      drop_table :"#{resource}_identifiers"
      drop_table :"#{resource}_versions"
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
