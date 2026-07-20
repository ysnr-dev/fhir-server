class AddReferenceSearchColumns < ActiveRecord::Migration[7.0]
  def change
    add_column :medication_requests, :encounter_reference, :string
    add_column :medication_requests, :requester_reference, :string
    add_column :service_requests, :encounter_reference, :string
    add_column :service_requests, :requester_reference, :string
    add_column :encounters, :service_provider_reference, :string
    add_column :locations, :partof_reference, :string
    add_column :organizations, :partof_reference, :string

    add_index :medication_requests, :encounter_reference
    add_index :medication_requests, :requester_reference
    add_index :service_requests, :encounter_reference
    add_index :service_requests, :requester_reference
    add_index :encounters, :service_provider_reference
    add_index :locations, :partof_reference
    add_index :organizations, :partof_reference
  end
end
