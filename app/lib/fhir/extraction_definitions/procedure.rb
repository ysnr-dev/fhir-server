module Fhir
  module ExtractionDefinitions
    module Procedure
      # category is 0..1 CodeableConcept. performed[x] is a choice: performedDateTime
      # (radiology / treatment perform records) or performedPeriod (surgery, with
      # start and end). Both feed the same pair of columns so `date` can search
      # either form: a dateTime fills start AND end with the same instant (so the
      # period semantics collapse to a point), a Period fills start and end
      # separately (end nil while the procedure is still ongoing).
      FIELDS = {
        status: { path: "status" },
        category_code: { path: "category", transform: :coding_code },
        code_value: { path: "code", transform: :coding_code },
        code_text: { path: "code", transform: :concept_text },
        subject_reference: { path: "subject.reference" },
        encounter_reference: { path: "encounter.reference" },
        performed_time: { path: "performedDateTime", fallback: "performedPeriod.start", transform: :datetime },
        performed_end: { path: "performedPeriod.end", fallback: "performedDateTime", transform: :datetime }
      }.freeze

      TOKENS = {
        "status"   => { path: "status", kind: :code },
        "category" => { path: "category", kind: :codeable_concept },
        "code"     => { path: "code", kind: :codeable_concept }
      }.freeze
    end
  end
end
