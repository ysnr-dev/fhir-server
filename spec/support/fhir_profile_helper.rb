module FhirProfileHelper
  # Runs the block under the given Fhir::Profile.mode (:off/:warn/:enforce),
  # restoring whatever mode was active before -- mirrors with_fhir_auth.
  def with_profile_mode(mode)
    previous = Fhir::Profile.mode
    Fhir::Profile.mode = mode
    yield
  ensure
    Fhir::Profile.mode = previous
  end
end

RSpec.configure do |config|
  config.include FhirProfileHelper, type: :request
end
