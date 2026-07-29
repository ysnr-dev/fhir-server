module Fhir
  module ExtractionDefinitions
    module QuestionnaireResponse
      # `questionnaire` is a canonical -- a bare URL string, not a Reference --
      # so it is extracted verbatim and searched as :uri. basedOn / partOf are
      # 0..* references matched by jsonb containment (see SearchDefinitions), so
      # they have no extracted column.
      FIELDS = {
        questionnaire_canonical: { path: "questionnaire" },
        status: { path: "status" },
        subject_reference: { path: "subject.reference" },
        encounter_reference: { path: "encounter.reference" },
        author_reference: { path: "author.reference" },
        source_reference: { path: "source.reference" },
        authored: { path: "authored", transform: :datetime }
      }.freeze

      TOKENS = {
        "status" => { path: "status", kind: :code }
      }.freeze
    end
  end
end
