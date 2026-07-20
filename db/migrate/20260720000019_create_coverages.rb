class CreateCoverages < ActiveRecord::Migration[7.0]
  def change
    create_table :coverages, id: :string do |t|
      t.integer :version_id, null: false, default: 1
      t.jsonb :content, null: false
      t.boolean :deleted, null: false, default: false
      t.datetime :last_updated, null: false

      # Search-optimized extracted fields
      t.string :status
      t.string :type_code
      t.string :type_text
      t.string :beneficiary_reference
      t.string :dependent

      t.timestamps
    end

    add_index :coverages, :status
    add_index :coverages, :type_code
    add_index :coverages, :beneficiary_reference
    add_index :coverages, :dependent
    add_index :coverages, :last_updated
    add_index :coverages, :deleted
    add_index :coverages, :content, using: :gin
  end
end
