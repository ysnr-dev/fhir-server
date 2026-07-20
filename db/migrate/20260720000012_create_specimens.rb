class CreateSpecimens < ActiveRecord::Migration[7.0]
  def change
    create_table :specimens, id: :string do |t|
      t.integer :version_id, null: false, default: 1
      t.jsonb :content, null: false
      t.boolean :deleted, null: false, default: false
      t.datetime :last_updated, null: false

      # Search-optimized extracted fields
      t.string :status
      t.string :type_code
      t.string :subject_reference
      t.string :accession_value
      t.datetime :collected_time

      t.timestamps
    end

    add_index :specimens, :status
    add_index :specimens, :type_code
    add_index :specimens, :subject_reference
    add_index :specimens, :accession_value
    add_index :specimens, :collected_time
    add_index :specimens, :last_updated
    add_index :specimens, :deleted
    add_index :specimens, :content, using: :gin
  end
end
