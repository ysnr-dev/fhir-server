# Launch context on tokens issued through the authorization_code flow. A token
# with patient_id is compartment-restricted; a client_credentials token leaves
# these NULL and keeps its unrestricted system-scope behaviour.
class AddPatientContextToAccessTokens < ActiveRecord::Migration[7.0]
  def change
    add_reference :access_tokens, :user, foreign_key: true
    add_column :access_tokens, :patient_id, :string
    # Lets a replayed authorization code revoke exactly the tokens it produced.
    add_reference :access_tokens, :authorization_code, foreign_key: true
  end
end
