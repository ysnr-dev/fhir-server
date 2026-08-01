module Fhir
  module ExtractionDefinitions
    module RelatedPerson
      # name is HumanName 0..*, so Patient's all_name_representations applies
      # verbatim -- kana/alias entries land in name_text. R4 defines no
      # family/given search params for RelatedPerson, only `name`, so unlike
      # Patient there are no separate family/given columns.
      # telecom/address are 0..* and, as on Patient, are left unextracted.
      FIELDS = {
        active: { path: "active" },
        patient_reference: { path: "patient.reference" },
        relationship_code: { path: "relationship", transform: :concept_list_code },
        name_text: { path: "name", transform: :all_name_representations },
        gender: { path: "gender" },
        birth_date: { path: "birthDate", transform: :partial_date }
      }.freeze

      TOKENS = {
        "gender"       => { path: "gender", kind: :code },
        "relationship" => { path: "relationship", kind: :codeable_concept_list }
      }.freeze
    end
  end
end
