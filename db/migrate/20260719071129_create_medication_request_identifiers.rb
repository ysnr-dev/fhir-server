class CreateMedicationRequestIdentifiers < ActiveRecord::Migration[7.0]
  def change
    create_table :medication_request_identifiers do |t|
      t.string :medication_request_id, null: false
      t.string :system
      t.string :value, null: false

      t.timestamps
    end

    add_foreign_key :medication_request_identifiers, :medication_requests
    add_index :medication_request_identifiers, :medication_request_id
    add_index :medication_request_identifiers, [:system, :value]
    add_index :medication_request_identifiers, :value
  end
end
