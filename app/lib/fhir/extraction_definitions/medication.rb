module Fhir
  module ExtractionDefinitions
    module Medication
      FIELDS = {
        status: { path: "status" },
        medication_code: { path: "code", transform: :coding_code },
        medication_text: { path: "code", transform: :concept_text },
        form_code: { path: "form", transform: :coding_code },
        manufacturer_reference: { path: "manufacturer.reference" }
      }.freeze

      TOKENS = {
        "status" => { path: "status", kind: :code },
        "code"   => { path: "code", kind: :codeable_concept },
        "form"   => { path: "form", kind: :codeable_concept }
      }.freeze
    end
  end
end
