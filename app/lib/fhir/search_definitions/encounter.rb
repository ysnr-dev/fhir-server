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
        "date"             => { type: :datetime, column: :period_start }
      }.freeze
    end
  end
end
