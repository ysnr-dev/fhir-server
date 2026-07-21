module Fhir
  # Feature switch for SMART Backend Services enforcement. Off by default so
  # local development and the test suite work without tokens; set
  # FHIR_AUTH_ENABLED=true to require a Bearer token (and matching system/*
  # scopes) on every FHIR endpoint. /metadata, /.well-known/smart-configuration,
  # and /oauth/token always stay public.
  module Auth
    mattr_accessor :enabled, default: ENV["FHIR_AUTH_ENABLED"] == "true"

    def self.enabled?
      !!enabled
    end
  end
end
