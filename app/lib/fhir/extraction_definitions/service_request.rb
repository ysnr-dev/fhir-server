module Fhir
  module ExtractionDefinitions
    module ServiceRequest
      FIELDS = {
        status: { path: "status" },
        intent: { path: "intent" },
        subject_reference: { path: "subject.reference" },
        encounter_reference: { path: "encounter.reference" },
        requester_reference: { path: "requester.reference" },
        authored_on: { path: "authoredOn", transform: :datetime },
        code: { path: "code", transform: :coding_code },
        code_text: { path: "code", transform: :concept_text }
      }.freeze

      TOKENS = {
        "status" => { path: "status", kind: :code },
        "intent" => { path: "intent", kind: :code },
        "code"   => { path: "code", kind: :codeable_concept }
      }.freeze
    end
  end
end
