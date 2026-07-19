class CreatePractitionerIdentifiers < ActiveRecord::Migration[7.0]
  def change
    create_table :practitioner_identifiers do |t|
      t.string :practitioner_id, null: false
      t.string :system
      t.string :value, null: false

      t.timestamps
    end

    add_foreign_key :practitioner_identifiers, :practitioners
    add_index :practitioner_identifiers, :practitioner_id
    add_index :practitioner_identifiers, [:system, :value]
    add_index :practitioner_identifiers, :value
  end
end
