module Fhir
  module SearchDefinitions
    module Binary
      # Binary has no standard search parameters (only _id/_lastUpdated, which
      # Fhir::Search provides for every type).
      PARAMS = {}.freeze
    end
  end
end
