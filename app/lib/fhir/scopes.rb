module Fhir
  # Parses and evaluates SMART (v1-style) system scopes for Backend Services:
  #   system/Patient.read   system/*.write   system/Encounter.*   system/*.*
  # patient/ and user/ contexts belong to the interactive SMART launch flows,
  # which this server does not implement -- such scopes are ignored if present.
  class Scopes
    PATTERN = %r{\Asystem/(\*|[A-Z][A-Za-z]*)\.(read|write|\*)\z}.freeze

    def self.valid?(scope)
      PATTERN.match?(scope)
    end

    def initialize(scopes)
      @grants = scopes.filter_map { |scope| PATTERN.match(scope)&.captures }
    end

    # access is :read or :write. Passing resource_type "*" (system-wide
    # endpoints like GET /_history) requires a wildcard-type grant.
    def allows?(resource_type, access)
      @grants.any? do |type, granted|
        (type == "*" || type == resource_type) && (granted == "*" || granted == access.to_s)
      end
    end
  end
end
