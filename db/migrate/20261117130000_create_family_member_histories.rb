class CreateFamilyMemberHistories < ActiveRecord::Migration[7.0]
  def change
    create_table :family_member_histories, id: :string do |t|
      t.integer :version_id, null: false, default: 1
      t.jsonb :content, null: false
      t.boolean :deleted, null: false, default: false
      t.datetime :last_updated, null: false

      # Search-optimized extracted fields
      t.string :status
      t.string :relationship_code
      t.string :sex_code
      t.string :code_text
      t.string :patient_reference
      t.datetime :recorded_time

      t.timestamps
    end

    add_index :family_member_histories, :status
    add_index :family_member_histories, :relationship_code
    add_index :family_member_histories, :sex_code
    add_index :family_member_histories, :code_text
    add_index :family_member_histories, :patient_reference
    add_index :family_member_histories, :recorded_time
    add_index :family_member_histories, :last_updated
    add_index :family_member_histories, :deleted
    add_index :family_member_histories, :content, using: :gin
  end
end
