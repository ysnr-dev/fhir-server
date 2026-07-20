module Fhir
  module SearchDefinitions
    module Encounter
      PARAMS = {
        "identifier" => { type: :identifier },
        "status"     => { type: :token, column: :status },
        "class"      => { type: :token, column: :class_code },
        "subject"          => { type: :reference, column: :subject_reference,
                                 target_type: "Patient", aliases: %w[patient] },
        "service-provider" => { type: :reference, column: :service_provider_reference, target_type: "Organization" },
        # Encounter.location[].location and Encounter.participant[].individual are
        # 0..* references, so they are matched by jsonb containment rather than an
        # extracted column.
        "location"         => { type: :reference, multiple: true, jsonb_key: "location",
                                 ref_path: %w[location reference], target_type: "Location" },
        "participant"      => { type: :reference, multiple: true, jsonb_key: "participant",
                                 ref_path: %w[individual reference], target_type: "Practitioner",
                                 aliases: %w[practitioner] },
        # eq is spec-correct containment (the search interval must fully contain
        # the period), not overlap; a NULL period.end means "still ongoing".
        "date"             => { type: :datetime, column: :period_start, end_column: :period_end }
      }.freeze
    end
  end
end
