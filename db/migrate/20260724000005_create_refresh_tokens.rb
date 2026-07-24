class CreateRefreshTokens < ActiveRecord::Migration[8.0]
  def change
    create_table :refresh_tokens do |t|
      t.string :token_digest, null: false
      t.string :oauth_client_id, null: false
      t.bigint :user_id, null: false
      t.string :patient_id, null: false
      t.string :scopes, null: false
      # The issuing authorization code anchors the whole grant: replay of a
      # rotated-out refresh token revokes every token descending from it.
      t.bigint :authorization_code_id, null: false
      t.datetime :expires_at, null: false
      t.datetime :used_at
      t.datetime :revoked_at
      t.timestamps

      t.index :token_digest, unique: true
      t.index :authorization_code_id
      t.index :oauth_client_id
      t.index :user_id
      t.index :expires_at
    end
  end
end
