module Fhir
  # Feature switch for SMART Backend Services enforcement. Defaults ON in
  # production (real data must never be exposed unauthenticated; an explicit
  # FHIR_AUTH_ENABLED=false there is rejected at boot by
  # config/initializers/production_guardrails.rb) and OFF elsewhere so local
  # development and the test suite work without tokens. /metadata,
  # /.well-known/smart-configuration, and /oauth/token always stay public.
  module Auth
    mattr_accessor :enabled,
                   default: ENV.fetch("FHIR_AUTH_ENABLED", Rails.env.production? ? "true" : "false") == "true"

    def self.enabled?
      !!enabled
    end
  end
end
