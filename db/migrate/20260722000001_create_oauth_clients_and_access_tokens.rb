# SMART Backend Services (machine-to-machine OAuth2 client_credentials):
# registered clients and the opaque bearer tokens issued to them. Secrets and
# tokens are stored as SHA-256 digests only.
class CreateOauthClientsAndAccessTokens < ActiveRecord::Migration[7.0]
  def change
    create_table :oauth_clients, id: :string do |t|
      t.string :name, null: false
      t.string :secret_digest, null: false
      # Space-separated SMART system scopes this client may be granted,
      # e.g. "system/*.read system/Patient.write"
      t.string :scopes, null: false
      t.timestamps
    end

    create_table :access_tokens do |t|
      t.string :token_digest, null: false
      t.references :oauth_client, null: false, foreign_key: true, type: :string
      t.string :scopes, null: false
      t.datetime :expires_at, null: false
      t.timestamps
    end
    add_index :access_tokens, :token_digest, unique: true
  end
end
