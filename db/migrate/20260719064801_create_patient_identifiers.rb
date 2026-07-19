class CreatePatientIdentifiers < ActiveRecord::Migration[7.0]
  def change
    create_table :patient_identifiers do |t|
      t.string :patient_id, null: false
      t.string :system
      t.string :value, null: false

      t.timestamps
    end

    add_foreign_key :patient_identifiers, :patients
    add_index :patient_identifiers, :patient_id
    add_index :patient_identifiers, [:system, :value]
    add_index :patient_identifiers, :value
  end
end
