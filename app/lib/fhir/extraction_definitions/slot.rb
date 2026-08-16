module Fhir
  module ExtractionDefinitions
    module Slot
      # Slot.start is an instant and the only one of the two ends R4 gives a search
      # parameter; the column is start_time because `start` is a SQL reserved word.
      FIELDS = {
        status: { path: "status" },
        appointment_type: { path: "appointmentType", transform: :coding_code },
        schedule_reference: { path: "schedule.reference" },
        start_time: { path: "start", transform: :datetime }
      }.freeze

      # As on Schedule, the three 0..* CodeableConcept elements are token rows only.
      TOKENS = {
        "status" => { path: "status", kind: :code },
        "appointment-type" => { path: "appointmentType", kind: :codeable_concept },
        "service-category" => { path: "serviceCategory", kind: :codeable_concept_list },
        "service-type" => { path: "serviceType", kind: :codeable_concept_list },
        "specialty" => { path: "specialty", kind: :codeable_concept_list }
      }.freeze
    end
  end
end
