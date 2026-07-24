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

  # A token as the interactive launch would mint it: patient-scoped and bound
  # to a launch context. Skips the browser flow so compartment enforcement can
  # be tested independently of it.
  def issue_patient_token(patient_id:, scopes: "patient/*.read", user: nil)
    client, = OauthClient.register(
      name: "spec-launch-#{SecureRandom.hex(4)}", scopes: scopes,
      redirect_uris: "https://app.example/cb", client_type: "public"
    )
    _record, raw = AccessToken.issue(client, scopes: scopes.split, user: user, patient_id: patient_id)
    raw
  end

  def register_user(patient_id:, email: nil, password: "correct-horse-battery")
    User.create!(
      email: email || "user-#{SecureRandom.hex(4)}@example.com",
      patient_id: patient_id,
      password: password
    )
  end

  def bearer_header(token)
    { "Authorization" => "Bearer #{token}" }
  end
end

RSpec.configure do |config|
  config.include FhirAuthHelper, type: :request
end
