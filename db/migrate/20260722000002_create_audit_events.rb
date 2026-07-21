# Server-generated access audit trail: one row per FHIR request (including
# denied ones). Rendered as FHIR AuditEvent resources by the read-only
# /AuditEvent endpoint; rows are never updated or deleted through the API.
class CreateAuditEvents < ActiveRecord::Migration[7.0]
  def change
    create_table :audit_events, id: :string do |t|
      t.datetime :occurred_at, null: false
      t.string :client_id      # OauthClient id when authenticated; NULL = anonymous
      t.string :client_name
      t.string :action, null: false       # AuditEvent.action: C R U D E
      t.string :interaction               # restful-interaction code; NULL when undeterminable
      t.string :resource_type
      t.string :resource_id
      t.string :request_method, null: false
      t.string :request_path, null: false # path incl. query string
      t.integer :response_status, null: false
      t.timestamps
    end

    add_index :audit_events, :occurred_at
    add_index :audit_events, %i[resource_type resource_id]
    add_index :audit_events, :client_id
  end
end
