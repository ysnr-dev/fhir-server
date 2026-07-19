class CreateMedicationRequestVersions < ActiveRecord::Migration[7.0]
  def change
    create_table :medication_request_versions do |t|
      t.string :medication_request_id, null: false
      t.integer :version_id, null: false
      t.jsonb :content, null: false
      t.boolean :deleted, null: false, default: false
      t.datetime :last_updated, null: false

      t.timestamps
    end

    add_index :medication_request_versions, [:medication_request_id, :version_id],
              unique: true, name: "index_med_request_versions_on_request_id_and_version_id"
  end
end
