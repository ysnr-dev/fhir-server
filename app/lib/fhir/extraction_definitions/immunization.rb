module Fhir
  module ExtractionDefinitions
    module Immunization
      # occurrence[x] is a choice; only occurrenceDateTime is extracted to the point
      # column. lotNumber is a plain string element.
      FIELDS = {
        status: { path: "status" },
        vaccine_code: { path: "vaccineCode", transform: :coding_code },
        vaccine_text: { path: "vaccineCode", transform: :concept_text },
        patient_reference: { path: "patient.reference" },
        occurrence_time: { path: "occurrenceDateTime", transform: :datetime },
        lot_number: { path: "lotNumber" }
      }.freeze

      TOKENS = {
        "status"       => { path: "status", kind: :code },
        "vaccine-code" => { path: "vaccineCode", kind: :codeable_concept }
      }.freeze
    end
  end
end
