class CreateFlags < ActiveRecord::Migration[7.0]
  def change
    create_table :flags, id: :string do |t|
      t.integer :version_id, null: false, default: 1
      t.jsonb :content, null: false
      t.boolean :deleted, null: false, default: false
      t.datetime :last_updated, null: false

      # Search-optimized extracted fields
      t.string :status
      t.string :category_code
      t.string :code_value
      t.string :code_text
      t.string :subject_reference
      t.string :encounter_reference
      t.string :author_reference
      # Flag.period is the interval the flag applies to. A NULL period_end means
      # the flag is still in effect (same convention as Encounter.period).
      t.datetime :period_start
      t.datetime :period_end

      t.timestamps
    end

    add_index :flags, :status
    add_index :flags, :category_code
    add_index :flags, :code_value
    add_index :flags, :subject_reference
    add_index :flags, :encounter_reference
    add_index :flags, :period_start
    add_index :flags, :last_updated
    add_index :flags, :deleted
    add_index :flags, :content, using: :gin
  end
end
