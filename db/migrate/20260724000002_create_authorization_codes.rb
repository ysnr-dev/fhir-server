# Short-lived, single-use OAuth2 authorization codes (RFC 6749 section 4.1)
# with PKCE (RFC 7636). Like access tokens, only the SHA-256 digest is stored.
# The patient context is frozen at issue time so a later change to the user's
# binding cannot retroactively widen an outstanding code.
class CreateAuthorizationCodes < ActiveRecord::Migration[7.0]
  def change
    create_table :authorization_codes do |t|
      t.string :code_digest, null: false
      t.references :oauth_client, null: false, foreign_key: true, type: :string
      t.references :user, null: false, foreign_key: true
      t.string :patient_id, null: false
      # Space-separated scopes the user actually consented to (a subset of what
      # the client requested, which is itself a subset of its registration).
      t.string :scopes, null: false
      # Re-verified at the token endpoint (RFC 6749 section 4.1.3).
      t.string :redirect_uri, null: false
      t.string :code_challenge, null: false
      t.string :code_challenge_method, null: false, default: "S256"
      t.datetime :expires_at, null: false
      # Single-use marker; a second presentation means the code leaked, so the
      # tokens it produced are revoked (RFC 6749 section 4.1.2).
      t.datetime :used_at
      t.timestamps
    end

    add_index :authorization_codes, :code_digest, unique: true
    add_index :authorization_codes, :expires_at
  end
end
