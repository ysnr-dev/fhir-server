# GET /.well-known/smart-configuration -- SMART discovery document, covering
# Backend Services (client_credentials), the standalone patient launch and the
# EHR launch on behalf of a practitioner (both authorization_code + PKCE).
class SmartConfigurationsController < ApplicationController
  def show
    render json: {
      "issuer" => base_url,
      "jwks_uri" => "#{base_url}/.well-known/jwks.json",
      "authorization_endpoint" => "#{base_url}/oauth/authorize",
      "token_endpoint" => "#{base_url}/oauth/token",
      "revocation_endpoint" => "#{base_url}/oauth/revoke",
      "introspection_endpoint" => "#{base_url}/oauth/introspect",
      "grant_types_supported" => %w[client_credentials authorization_code refresh_token],
      "response_types_supported" => ["code"],
      # S256 only: "plain" offers no protection against an intercepted code.
      "code_challenge_methods_supported" => ["S256"],
      "token_endpoint_auth_methods_supported" => %w[private_key_jwt client_secret_basic client_secret_post],
      "token_endpoint_auth_signing_alg_values_supported" => Fhir::ClientAssertion::ALGORITHMS,
      "id_token_signing_alg_values_supported" => [Fhir::SigningKey::ALG],
      "scopes_supported" => %w[
        system/*.read system/*.write system/*.* system/*.rs system/*.cud system/*.cruds
        patient/*.read patient/*.rs
        user/*.read user/*.write user/*.* user/*.rs user/*.cud user/*.cruds
        launch launch/patient launch/encounter
        offline_access online_access openid fhirUser profile
      ],
      "capabilities" => %w[
        launch-ehr
        launch-standalone
        context-ehr-patient
        context-ehr-encounter
        context-standalone-patient
        context-banner
        sso-openid-connect
        permission-patient
        permission-user
        permission-v1
        permission-v2
        permission-offline
        permission-online
        client-public
        client-confidential-asymmetric
        client-confidential-symmetric
      ]
    }
  end
end
