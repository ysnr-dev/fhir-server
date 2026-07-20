module Fhir
  module ExtractionDefinitions
    module Encounter
      # Encounter.class is a bare Coding (not a CodeableConcept), so class_code digs
      # `class.code` directly. Encounter.location/participant are matched by jsonb
      # containment (see SearchDefinitions), so they have no extracted column here.
      FIELDS = {
        status: { path: "status" },
        class_code: { path: "class.code" },
        subject_reference: { path: "subject.reference" },
        service_provider_reference: { path: "serviceProvider.reference" },
        period_start: { path: "period.start", transform: :datetime },
        period_end: { path: "period.end", transform: :datetime }
      }.freeze
    end
  end
end
