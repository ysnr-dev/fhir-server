class CreateMedicationRequests < ActiveRecord::Migration[7.0]
  def change
    create_table :medication_requests, id: :string do |t|
      t.integer :version_id, null: false, default: 1
      t.jsonb :content, null: false
      t.boolean :deleted, null: false, default: false
      t.datetime :last_updated, null: false

      # Search-optimized extracted fields
      t.string :status
      t.string :intent
      t.string :subject_reference
      t.datetime :authored_on
      t.string :medication_code
      t.string :medication_text

      t.timestamps
    end

    add_index :medication_requests, :status
    add_index :medication_requests, :intent
    add_index :medication_requests, :subject_reference
    add_index :medication_requests, :authored_on
    add_index :medication_requests, :medication_code
    add_index :medication_requests, :medication_text
    add_index :medication_requests, :last_updated
    add_index :medication_requests, :deleted
    add_index :medication_requests, :content, using: :gin
  end
end
