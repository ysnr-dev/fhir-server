module Fhir
  module ExtractionDefinitions
    module Procedure
      # category is 0..1 CodeableConcept. performed[x] is a choice; only
      # performedDateTime is extracted to the point column.
      FIELDS = {
        status: { path: "status" },
        category_code: { path: "category", transform: :coding_code },
        code_value: { path: "code", transform: :coding_code },
        code_text: { path: "code", transform: :concept_text },
        subject_reference: { path: "subject.reference" },
        encounter_reference: { path: "encounter.reference" },
        performed_time: { path: "performedDateTime", transform: :datetime }
      }.freeze
    end
  end
end
