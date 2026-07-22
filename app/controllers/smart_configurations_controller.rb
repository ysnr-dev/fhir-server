# GET /.well-known/smart-configuration -- SMART discovery document. Only the
# Backend Services subset is implemented, so no authorize endpoint or launch
# capabilities are advertised.
class SmartConfigurationsController < ApplicationController
  def show
    render json: {
      "token_endpoint" => "#{base_url}/oauth/token",
      "revocation_endpoint" => "#{base_url}/oauth/revoke",
      "grant_types_supported" => ["client_credentials"],
      "token_endpoint_auth_methods_supported" => %w[private_key_jwt client_secret_basic client_secret_post],
      "token_endpoint_auth_signing_alg_values_supported" => Fhir::ClientAssertion::ALGORITHMS,
      "scopes_supported" => %w[system/*.read system/*.write system/*.*],
      "capabilities" => %w[client-confidential-asymmetric client-confidential-symmetric]
    }
  end
end
