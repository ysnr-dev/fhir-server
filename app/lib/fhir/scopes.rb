module Fhir
  # Parses and evaluates SMART scopes in two families, accepting both the v1
  # access keywords and the v2 CRUDS interaction letters:
  #
  #   system/Patient.read  system/*.write  system/Encounter.*  system/*.*
  #   system/Patient.rs    system/*.cud    system/Encounter.cruds
  #     Backend Services. Unrestricted across the whole server.
  #
  #   patient/Observation.read  patient/*.read  patient/Observation.rs
  #     Interactive standalone launch. Read-only, and only meaningful on a token
  #     that carries a patient launch context -- the context, not the scope, is
  #     what confines reads to one compartment (Fhir::PatientContext).
  #
  #   offline_access  online_access
  #     Context scopes (SMART App Launch): they ask for a refresh token and
  #     grant no resource access themselves, so #parse ignores them and they
  #     never satisfy #allows?. Only the interactive flow honours them.
  #
  #   openid  fhirUser  profile
  #     Identity scopes (OpenID Connect): they ask for an id_token identifying
  #     the logged-in user. Like the refresh context scopes, they grant no
  #     resource access. `openid` triggers the id_token; `fhirUser`/`profile`
  #     add the fhirUser claim to it.
  #
  # This server enforces only two coarse permissions, :read and :write, so every
  # access form collapses onto them:
  #   :read  <- v1 "read";  v2 r (read) or s (search)
  #   :write <- v1 "write"; v2 c (create), u (update) or d (delete)
  #   both   <- v1 "*";     v2 any mix spanning the two groups (e.g. "cruds")
  # The finer CRUDS distinctions and the v2 ?query search-parameter constraints
  # are not modelled: a constrained scope (patient/Observation.rs?category=x)
  # would have to be honoured by narrowing, and silently ignoring the constraint
  # would over-grant, so such scopes are treated as invalid for now.
  #
  # user/ scopes belong to the interactive provider-facing flows, which this
  # server does not implement -- such scopes are ignored if present.
  #
  # Note the asymmetry in `allows?("*", :read)`: a wildcard-type check is how
  # server-wide endpoints (GET /_history) ask "may this token see everything?",
  # and `patient/*.read` satisfies it structurally without meaning it. Those
  # endpoints must use #system_allows? instead.
  class Scopes
    SYSTEM_PATTERN = %r{\Asystem/(\*|[A-Z][A-Za-z]*)\.([a-z*]+)\z}
    PATIENT_PATTERN = %r{\Apatient/(\*|[A-Z][A-Za-z]*)\.([a-z*]+)\z}
    # v2 access: the CRUDS letters in canonical order, no repeats, at least one
    # present. The lookahead rejects the empty string that c?r?u?d?s? would
    # otherwise match.
    V2_ACCESS = /\A(?=[cruds])c?r?u?d?s?\z/
    REFRESH_SCOPES = %w[offline_access online_access].freeze
    IDENTITY_SCOPES = %w[openid fhirUser profile].freeze
    # Context scopes carry no resource access; they request refresh/identity
    # tokens instead. Grouped together for the "must accompany a patient/ scope"
    # registration rule, split apart where behaviour differs (see the helpers).
    CONTEXT_SCOPES = (REFRESH_SCOPES + IDENTITY_SCOPES).freeze

    # Maps a v1 keyword or v2 CRUDS access string onto the coarse permissions
    # this server enforces. Returns an array of :read/:write, or nil if the
    # access is not a recognised form.
    def self.access_for(access)
      case access
      when "read"  then [:read]
      when "write" then [:write]
      when "*"     then %i[read write]
      when V2_ACCESS
        permissions = []
        permissions << :read if access.match?(/[rs]/)
        permissions << :write if access.match?(/[cud]/)
        permissions
      end
    end

    def self.valid?(scope)
      valid_system?(scope) || valid_patient?(scope) || valid_context?(scope)
    end

    def self.valid_system?(scope)
      return false unless (match = SYSTEM_PATTERN.match(scope))

      !access_for(match[2]).nil?
    end

    # Phase 1 grants no write through the interactive flow, so a patient/ scope
    # that asks for any write access (v1 .write/.*, or a v2 string containing
    # c/u/d) is not merely unhandled -- it is invalid.
    def self.valid_patient?(scope)
      return false unless (match = PATIENT_PATTERN.match(scope))

      access = access_for(match[2])
      access.present? && access.exclude?(:write)
    end

    def self.valid_context?(scope)
      CONTEXT_SCOPES.include?(scope)
    end

    # Whether this scope list asks for a refresh token at all.
    def self.refresh_requested?(scopes)
      scopes.intersect?(REFRESH_SCOPES)
    end

    # Whether this scope list asks for an OpenID Connect id_token. `openid` is
    # the trigger; fhirUser/profile only shape its claims, so on their own they
    # produce no id_token.
    def self.identity_requested?(scopes)
      scopes.include?("openid")
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
      if (match = SYSTEM_PATTERN.match(scope)) && (access = self.class.access_for(match[2]))
        [:system, match[1], access]
      elsif (match = PATIENT_PATTERN.match(scope)) &&
            (access = self.class.access_for(match[2])) && access.exclude?(:write)
        [:patient, match[1], access]
      end
    end

    def matches?(grant, resource_type, access)
      _family, type, granted = grant
      (type == "*" || type == resource_type) && granted.include?(access)
    end
  end
end
