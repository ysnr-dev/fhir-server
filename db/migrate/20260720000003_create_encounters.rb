class CreateEncounters < ActiveRecord::Migration[7.0]
  def change
    create_table :encounters, id: :string do |t|
      t.integer :version_id, null: false, default: 1
      t.jsonb :content, null: false
      t.boolean :deleted, null: false, default: false
      t.datetime :last_updated, null: false

      # Search-optimized extracted fields
      t.string :status
      t.string :class_code
      t.string :subject_reference
      t.datetime :period_start

      t.timestamps
    end

    add_index :encounters, :status
    add_index :encounters, :class_code
    add_index :encounters, :subject_reference
    add_index :encounters, :period_start
    add_index :encounters, :last_updated
    add_index :encounters, :deleted
    add_index :encounters, :content, using: :gin
  end
end
