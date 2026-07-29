module Fhir
  module ExtractionDefinitions
    module Questionnaire
      # Questionnaire is definitional: no Reference elements, so nothing here
      # feeds the patient compartment. `subjectType` is 0..* code in base R4
      # (JASPEHR narrows it to 1..1) and `code` is 0..* bare Coding, so both
      # flatten to their first entry for the sort/display column while TOKENS
      # below keeps every value searchable.
      FIELDS = {
        url: { path: "url" },
        version: { path: "version" },
        name: { path: "name" },
        title: { path: "title" },
        status: { path: "status" },
        subject_type: { path: "subjectType", transform: :first_value },
        publisher: { path: "publisher" },
        code_value: { path: "code", transform: :coding_list_code },
        questionnaire_date: { path: "date", transform: :datetime }
      }.freeze

      TOKENS = {
        "status" => { path: "status", kind: :code },
        "version" => { path: "version", kind: :code },
        "subject-type" => { path: "subjectType", kind: :code_list },
        "code" => { path: "code", kind: :coding_list }
      }.freeze
    end
  end
end
