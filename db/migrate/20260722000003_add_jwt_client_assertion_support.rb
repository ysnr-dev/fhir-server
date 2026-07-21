# SMART Backend Services asymmetric client authentication (private_key_jwt):
# clients may register a JWKS instead of a shared secret, and used assertion
# jtis are remembered until their exp to prevent replay.
class AddJwtClientAssertionSupport < ActiveRecord::Migration[7.0]
  def change
    add_column :oauth_clients, :jwks, :jsonb
    change_column_null :oauth_clients, :secret_digest, true

    create_table :client_assertion_jtis do |t|
      t.string :oauth_client_id, null: false
      t.string :jti, null: false
      t.datetime :expires_at, null: false
      t.datetime :created_at, null: false
    end
    add_index :client_assertion_jtis, %i[oauth_client_id jti], unique: true
    add_index :client_assertion_jtis, :expires_at
  end
end
