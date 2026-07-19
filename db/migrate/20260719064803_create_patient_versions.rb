class CreatePatientVersions < ActiveRecord::Migration[7.0]
  def change
    create_table :patient_versions do |t|
      t.string :patient_id, null: false
      t.integer :version_id, null: false
      t.jsonb :content, null: false
      t.boolean :deleted, null: false, default: false
      t.datetime :last_updated, null: false

      t.timestamps
    end

    add_index :patient_versions, [:patient_id, :version_id], unique: true
  end
end
