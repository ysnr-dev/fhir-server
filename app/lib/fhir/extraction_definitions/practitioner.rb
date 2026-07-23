module Fhir
  module ExtractionDefinitions
    module Practitioner
      FIELDS = {
        active: { path: "active" },
        gender: { path: "gender" },
        birth_date: { path: "birthDate", transform: :partial_date },
        family: { path: "name", transform: :official_family },
        given: { path: "name", transform: :official_given },
        name_text: { path: "name", transform: :all_name_representations }
      }.freeze

      TOKENS = {
        "gender" => { path: "gender", kind: :code }
      }.freeze
    end
  end
end
