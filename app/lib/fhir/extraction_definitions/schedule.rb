module Fhir
  module ExtractionDefinitions
    module Schedule
      # Schedule.actor is 1..* and matched by jsonb containment (see
      # SearchDefinitions), so it has no extracted column.
      FIELDS = {
        active: { path: "active" },
        planning_horizon_start: { path: "planningHorizon.start", transform: :datetime },
        planning_horizon_end: { path: "planningHorizon.end", transform: :datetime }
      }.freeze

      # serviceCategory / serviceType / specialty are 0..* CodeableConcept: one
      # schedule can be both "一般外来" and "予防接種", so every coding of every
      # concept becomes a token row rather than being flattened to a column.
      TOKENS = {
        "service-category" => { path: "serviceCategory", kind: :codeable_concept_list },
        "service-type" => { path: "serviceType", kind: :codeable_concept_list },
        "specialty" => { path: "specialty", kind: :codeable_concept_list }
      }.freeze
    end
  end
end
