module Fhir
  module ExtractionDefinitions
    module DocumentReference
      FIELDS = {
        status: { path: "status" },
        doc_status: { path: "docStatus" },
        type_code: { path: "type", transform: :coding_code },
        type_text: { path: "type", transform: :concept_text },
        subject_reference: { path: "subject.reference" },
        document_date: { path: "date", transform: :datetime }
      }.freeze

      TOKENS = {
        "status" => { path: "status", kind: :code },
        "type"   => { path: "type", kind: :codeable_concept }
      }.freeze
    end
  end
end
