class AddNonceToAuthorizationCodes < ActiveRecord::Migration[8.0]
  def change
    # OpenID Connect nonce: carried from the authorization request to the
    # id_token so the client can bind the token to its own session (optional,
    # so nullable).
    add_column :authorization_codes, :nonce, :string
  end
end
