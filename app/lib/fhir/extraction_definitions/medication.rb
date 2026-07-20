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
    end
  end
end
