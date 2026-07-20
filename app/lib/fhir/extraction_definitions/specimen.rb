module Fhir
  module ExtractionDefinitions
    module Specimen
      # collection.collected[x] is a choice; only collectedDateTime is extracted to
      # the point column. accessionIdentifier is a single Identifier searched by token.
      FIELDS = {
        status: { path: "status" },
        type_code: { path: "type", transform: :coding_code },
        subject_reference: { path: "subject.reference" },
        accession_value: { path: "accessionIdentifier.value" },
        collected_time: { path: "collection.collectedDateTime", transform: :datetime }
      }.freeze
    end
  end
end
