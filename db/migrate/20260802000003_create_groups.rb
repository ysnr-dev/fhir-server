class CreateGroups < ActiveRecord::Migration[8.0]
  def change
    create_table :groups, id: :string do |t|
      t.integer :version_id, null: false, default: 1
      t.jsonb :content, null: false
      t.boolean :deleted, null: false, default: false
      t.datetime :last_updated, null: false

      # Search-optimized extracted fields (match ExtractionDefinitions::Group::FIELDS).
      # Group.type is stored as group_type: a column literally named `type` would
      # switch Rails single-table inheritance on for this model.
      # Group.member is 0..* and is matched by jsonb containment, so it has no
      # column -- which also means Group has no patient-compartment membership.
      t.string :group_type
      t.boolean :actual
      t.string :code_value
      t.string :managing_entity_reference

      t.timestamps
    end

    add_index :groups, :group_type
    add_index :groups, :actual
    add_index :groups, :code_value
    add_index :groups, :managing_entity_reference
    add_index :groups, :last_updated
    add_index :groups, :deleted
    add_index :groups, :content, using: :gin
  end
end
