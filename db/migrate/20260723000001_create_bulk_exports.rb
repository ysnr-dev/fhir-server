# Bulk Data Access IG (v2.0.0) $export job tracking. NDJSON output is stored
# in Postgres (bulk_export_files.content) rather than external object storage,
# since the Render free-tier web dyno has no persistent disk -- see
# BulkExportGenerator for the size caps that keep this bounded.
class CreateBulkExports < ActiveRecord::Migration[8.0]
  def change
    create_table :bulk_exports, id: :string do |t|
      t.string :kind, null: false             # "system" or "patient" ($export scope)
      t.string :status, null: false, default: "in_progress" # in_progress|completed|failed|cancelled
      t.jsonb :types                           # requested _type list, nil = every registered type
      t.datetime :since                        # requested _since
      t.string :output_format, null: false
      t.datetime :transaction_time             # snapshot instant; only resources up to this are included
      t.string :request_url, null: false
      t.string :oauth_client_id                # nil when auth is disabled
      t.text :error_message
      t.string :group_id                       # reserved for a future Group/$export
      t.timestamps
    end

    add_index :bulk_exports, :status
    add_index :bulk_exports, :oauth_client_id
    add_index :bulk_exports, :created_at

    create_table :bulk_export_files, id: :string do |t|
      t.string :bulk_export_id, null: false
      t.string :resource_type, null: false
      t.integer :sequence, null: false, default: 1
      t.text :content, null: false
      t.integer :resource_count, null: false
      t.integer :byte_size, null: false
      t.timestamps
    end

    add_index :bulk_export_files, :bulk_export_id
    add_foreign_key :bulk_export_files, :bulk_exports, on_delete: :cascade
  end
end
