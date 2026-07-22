module Fhir
  module ExtractionDefinitions
    module Binary
      # contentType is extracted for information only; Binary defines no
      # standard search parameters.
      FIELDS = {
        content_type: { path: "contentType" }
      }.freeze
    end
  end
end
