module FhirAuthHelper
  # Enables SMART enforcement for the block only; the suite default stays off.
  def with_fhir_auth
    Fhir::Auth.enabled = true
    yield
  ensure
    Fhir::Auth.enabled = false
  end

  # Registers a client and returns a raw bearer token carrying the given scopes.
  def issue_access_token(scopes: "system/*.*")
    client, = OauthClient.register(name: "spec-client-#{SecureRandom.hex(4)}", scopes: scopes)
    _record, raw = AccessToken.issue(client, scopes: scopes.split)
    raw
  end

  def bearer_header(token)
    { "Authorization" => "Bearer #{token}" }
  end
end

RSpec.configure do |config|
  config.include FhirAuthHelper, type: :request
end
