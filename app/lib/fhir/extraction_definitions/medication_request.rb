module Fhir
  module ExtractionDefinitions
    module MedicationRequest
      FIELDS = {
        status: { path: "status" },
        intent: { path: "intent" },
        subject_reference: { path: "subject.reference" },
        encounter_reference: { path: "encounter.reference" },
        requester_reference: { path: "requester.reference" },
        authored_on: { path: "authoredOn", transform: :datetime },
        medication_code: { path: "medicationCodeableConcept", transform: :coding_code },
        medication_text: { path: "medicationCodeableConcept", transform: :concept_text }
      }.freeze

      TOKENS = {
        "status" => { path: "status", kind: :code },
        "intent" => { path: "intent", kind: :code },
        "code"   => { path: "medicationCodeableConcept", kind: :codeable_concept }
      }.freeze
    end
  end
end
