class CreateServiceRequestIdentifiers < ActiveRecord::Migration[7.0]
  def change
    create_table :service_request_identifiers do |t|
      t.string :service_request_id, null: false
      t.string :system
      t.string :value, null: false

      t.timestamps
    end

    add_foreign_key :service_request_identifiers, :service_requests
    add_index :service_request_identifiers, :service_request_id
    add_index :service_request_identifiers, [:system, :value]
    add_index :service_request_identifiers, :value
  end
end
