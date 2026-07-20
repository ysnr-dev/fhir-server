module Fhir
  module ExtractionDefinitions
    module Organization
      FIELDS = {
        active: { path: "active" },
        name: { path: "name" },
        partof_reference: { path: "partOf.reference" }
      }.freeze
    end
  end
end
