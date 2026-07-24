module Fhir
  # Parses and evaluates SMART (v1-style) scopes in two families:
  #
  #   system/Patient.read  system/*.write  system/Encounter.*  system/*.*
  #     Backend Services. Unrestricted across the whole server.
  #
  #   patient/Observation.read  patient/*.read
  #     Interactive standalone launch. Read-only, and only meaningful on a token
  #     that carries a patient launch context -- the context, not the scope, is
  #     what confines reads to one compartment (Fhir::PatientContext).
  #
  # user/ scopes belong to the interactive provider-facing flows, which this
  # server does not implement -- such scopes are ignored if present.
  #
  # Note the asymmetry in `allows?("*", :read)`: a wildcard-type check is how
  # server-wide endpoints (GET /_history) ask "may this token see everything?",
  # and `patient/*.read` satisfies it structurally without meaning it. Those
  # endpoints must use #system_allows? instead.
  class Scopes
    SYSTEM_PATTERN = %r{\Asystem/(\*|[A-Z][A-Za-z]*)\.(read|write|\*)\z}
    # Phase 1 grants no write through the interactive flow, so patient/X.write
    # and patient/X.* are not merely unhandled -- they are invalid.
    PATIENT_PATTERN = %r{\Apatient/(\*|[A-Z][A-Za-z]*)\.(read)\z}

    def self.valid?(scope)
      valid_system?(scope) || valid_patient?(scope)
    end

    def self.valid_system?(scope)
      SYSTEM_PATTERN.match?(scope)
    end

    def self.valid_patient?(scope)
      PATIENT_PATTERN.match?(scope)
    end

    def initialize(scopes)
      @grants = scopes.filter_map { |scope| parse(scope) }
    end

    # access is :read or :write. Passing resource_type "*" (system-wide
    # endpoints like GET /_history) requires a wildcard-type grant.
    def allows?(resource_type, access)
      @grants.any? { |grant| matches?(grant, resource_type, access) }
    end

    # Same check restricted to the system/ family: for interactions that expose
    # data beyond a single compartment and therefore cannot be satisfied by a
    # patient-context token at all.
    def system_allows?(resource_type, access)
      @grants.any? { |grant| grant[0] == :system && matches?(grant, resource_type, access) }
    end

    def patient_grants?
      @grants.any? { |grant| grant[0] == :patient }
    end

    private

    def parse(scope)
      if (match = SYSTEM_PATTERN.match(scope))
        [:system, *match.captures]
      elsif (match = PATIENT_PATTERN.match(scope))
        [:patient, *match.captures]
      end
    end

    def matches?(grant, resource_type, access)
      _family, type, granted = grant
      (type == "*" || type == resource_type) && (granted == "*" || granted == access.to_s)
    end
  end
end
