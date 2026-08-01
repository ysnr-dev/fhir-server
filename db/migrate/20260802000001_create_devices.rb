class CreateDevices < ActiveRecord::Migration[8.0]
  def change
    create_table :devices, id: :string do |t|
      t.integer :version_id, null: false, default: 1
      t.jsonb :content, null: false
      t.boolean :deleted, null: false, default: false
      t.datetime :last_updated, null: false

      # Search-optimized extracted fields (match ExtractionDefinitions::Device::FIELDS).
      # patient_reference is what places Device in the patient compartment; it is
      # 0..1 in FHIR, so a shared ward device simply belongs to no compartment.
      t.string :status
      t.string :type_code
      t.string :patient_reference
      t.string :owner_reference
      t.string :location_reference
      t.string :manufacturer
      t.string :model_number
      t.string :device_name_text
      t.string :url

      t.timestamps
    end

    add_index :devices, :status
    add_index :devices, :type_code
    add_index :devices, :patient_reference
    add_index :devices, :owner_reference
    add_index :devices, :location_reference
    add_index :devices, :manufacturer
    add_index :devices, :model_number
    add_index :devices, :device_name_text
    add_index :devices, :url
    add_index :devices, :last_updated
    add_index :devices, :deleted
    add_index :devices, :content, using: :gin
  end
end
