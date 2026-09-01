class CreateProvenances < ActiveRecord::Migration[8.0]
  def change
    create_table :provenances, id: :string do |t|
      t.integer :version_id, null: false, default: 1
      t.jsonb :content, null: false
      t.boolean :deleted, null: false, default: false
      t.datetime :last_updated, null: false

      # Search-optimized extracted fields (match ExtractionDefinitions::Provenance::FIELDS).
      # Provenance.target / .agent / .signature are 0..* and matched by jsonb
      # containment (target, agent) or resource_tokens rows (agent-type,
      # signature-type), so `recorded` is the only element with a column.
      t.datetime :recorded

      t.timestamps
    end

    add_index :provenances, :recorded
    add_index :provenances, :last_updated
    add_index :provenances, :deleted
    add_index :provenances, :content, using: :gin
  end
end
