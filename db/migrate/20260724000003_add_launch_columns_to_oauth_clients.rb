# Interactive SMART launch clients: they redirect a browser back to a
# registered URI, and public ones (SPAs, native apps) hold no secret at all --
# PKCE is what proves the token request came from the app that started the flow.
class AddLaunchColumnsToOauthClients < ActiveRecord::Migration[7.0]
  def change
    # Space-separated (same convention as `scopes`). Matched exactly; no
    # wildcards, no prefix matching -- that is what keeps this from being an
    # open redirector.
    add_column :oauth_clients, :redirect_uris, :string
    # "confidential" (existing backend + web-server clients) or "public".
    add_column :oauth_clients, :client_type, :string, null: false, default: "confidential"
  end
end
