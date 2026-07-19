class CreatePractitioners < ActiveRecord::Migration[7.0]
  def change
    create_table :practitioners, id: :string do |t|
      t.integer :version_id, null: false, default: 1
      t.jsonb :content, null: false
      t.boolean :deleted, null: false, default: false
      t.datetime :last_updated, null: false

      # Search-optimized extracted fields
      t.boolean :active
      t.string :family
      t.string :given
      t.string :name_text
      t.string :gender
      t.date :birth_date

      t.timestamps
    end

    add_index :practitioners, :gender
    add_index :practitioners, :birth_date
    add_index :practitioners, :last_updated
    add_index :practitioners, :family
    add_index :practitioners, :name_text
    add_index :practitioners, :deleted
    add_index :practitioners, :content, using: :gin
  end
end
