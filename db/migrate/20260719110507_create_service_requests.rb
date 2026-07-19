class CreateServiceRequests < ActiveRecord::Migration[7.0]
  def change
    create_table :service_requests, id: :string do |t|
      t.integer :version_id, null: false, default: 1
      t.jsonb :content, null: false
      t.boolean :deleted, null: false, default: false
      t.datetime :last_updated, null: false

      # Search-optimized extracted fields
      t.string :status
      t.string :intent
      t.string :subject_reference
      t.datetime :authored_on
      t.string :code
      t.string :code_text

      t.timestamps
    end

    add_index :service_requests, :status
    add_index :service_requests, :intent
    add_index :service_requests, :subject_reference
    add_index :service_requests, :authored_on
    add_index :service_requests, :code
    add_index :service_requests, :code_text
    add_index :service_requests, :last_updated
    add_index :service_requests, :deleted
    add_index :service_requests, :content, using: :gin
  end
end
