class CreateCompositions < ActiveRecord::Migration[7.0]
  def change
    create_table :compositions, id: :string do |t|
      t.integer :version_id, null: false, default: 1
      t.jsonb :content, null: false
      t.boolean :deleted, null: false, default: false
      t.datetime :last_updated, null: false

      # Search-optimized extracted fields (match ExtractionDefinitions::Composition::FIELDS).
      # Composition.author is 0..* / 1..*, matched by jsonb containment, so it has no column.
      t.string :status
      t.string :type_code
      t.string :type_text
      t.string :category_code
      t.string :subject_reference
      t.string :encounter_reference
      t.datetime :composition_date

      t.timestamps
    end

    add_index :compositions, :status
    add_index :compositions, :type_code
    add_index :compositions, :category_code
    add_index :compositions, :subject_reference
    add_index :compositions, :encounter_reference
    add_index :compositions, :composition_date
    add_index :compositions, :last_updated
    add_index :compositions, :deleted
    add_index :compositions, :content, using: :gin
  end
end
