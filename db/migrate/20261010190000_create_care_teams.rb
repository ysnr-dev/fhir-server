class CreateCareTeams < ActiveRecord::Migration[7.0]
  def change
    create_table :care_teams, id: :string do |t|
      t.integer :version_id, null: false, default: 1
      t.jsonb :content, null: false
      t.boolean :deleted, null: false, default: false
      t.datetime :last_updated, null: false

      # Search-optimized extracted fields
      t.string :status
      t.string :category_code
      t.string :name
      t.string :subject_reference
      t.string :encounter_reference
      t.string :managing_organization_reference
      t.datetime :period_start
      t.datetime :period_end

      t.timestamps
    end

    add_index :care_teams, :status
    add_index :care_teams, :category_code
    add_index :care_teams, :name
    add_index :care_teams, :subject_reference
    add_index :care_teams, :encounter_reference
    add_index :care_teams, :last_updated
    add_index :care_teams, :deleted
    add_index :care_teams, :content, using: :gin
  end
end
