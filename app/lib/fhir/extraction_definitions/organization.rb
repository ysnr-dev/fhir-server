module Fhir
  module ExtractionDefinitions
    module Organization
      FIELDS = {
        active: { path: "active" },
        name: { path: "name" },
        partof_reference: { path: "partOf.reference" }
      }.freeze

      # Organization has no token search params (name is string, active is boolean).
      TOKENS = {}.freeze
    end
  end
end
