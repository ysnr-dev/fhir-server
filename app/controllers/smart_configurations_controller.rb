# GET /.well-known/smart-configuration -- SMART discovery document. Only the
# Backend Services subset is implemented, so no authorize endpoint or launch
# capabilities are advertised.
class SmartConfigurationsController < ApplicationController
  def show
    render json: {
      "token_endpoint" => "#{base_url}/oauth/token",
      "grant_types_supported" => ["client_credentials"],
      "token_endpoint_auth_methods_supported" => %w[client_secret_basic client_secret_post],
      "scopes_supported" => %w[system/*.read system/*.write system/*.*],
      "capabilities" => ["client-confidential-symmetric"]
    }
  end
end
