module Fhir
  module ExtractionDefinitions
    module Coverage
      # payor is 1..* reference matched via jsonb containment (see SearchDefinitions),
      # so it is not extracted to a column here.
      FIELDS = {
        status: { path: "status" },
        type_code: { path: "type", transform: :coding_code },
        type_text: { path: "type", transform: :concept_text },
        beneficiary_reference: { path: "beneficiary.reference" },
        dependent: { path: "dependent" }
      }.freeze

      TOKENS = {
        "status" => { path: "status", kind: :code },
        "type"   => { path: "type", kind: :codeable_concept }
      }.freeze
    end
  end
end
