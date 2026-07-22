class CreateDocumentReferencesAndBinaries < ActiveRecord::Migration[7.0]
  def change
    create_table :document_references, id: :string do |t|
      t.integer :version_id, null: false, default: 1
      t.jsonb :content, null: false
      t.boolean :deleted, null: false, default: false
      t.datetime :last_updated, null: false

      # Search-optimized extracted fields
      t.string :status
      t.string :doc_status
      t.string :type_code
      t.string :type_text
      t.string :subject_reference
      t.datetime :document_date

      t.timestamps
    end

    add_index :document_references, :status
    add_index :document_references, :type_code
    add_index :document_references, :subject_reference
    add_index :document_references, :document_date
    add_index :document_references, :last_updated
    add_index :document_references, :deleted
    add_index :document_references, :content, using: :gin

    # Binary has no standard search parameters; only the base columns plus the
    # extracted contentType (informational). The base64 payload lives in content.
    create_table :binaries, id: :string do |t|
      t.integer :version_id, null: false, default: 1
      t.jsonb :content, null: false
      t.boolean :deleted, null: false, default: false
      t.datetime :last_updated, null: false

      t.string :content_type

      t.timestamps
    end

    add_index :binaries, :last_updated
    add_index :binaries, :deleted
  end
end
