module Fhir
  module SearchDefinitions
    module RelatedPerson
      PARAMS = {
        "identifier"   => { type: :identifier },
        # name_text is a space-joined multi-token column (see the extraction
        # definition), so a plain prefix match would only hit the first token.
        "name"         => { type: :string, column: :name_text, word_boundary: true },
        "gender"       => { type: :token, column: :gender },
        "birthdate"    => { type: :date, column: :birth_date },
        # patient is 1..1 in FHIR, so every RelatedPerson is in a compartment.
        "patient"      => { type: :reference, column: :patient_reference, target_type: "Patient" },
        "relationship" => { type: :token, column: :relationship_code },
        "active"       => { type: :boolean, column: :active }
      }.freeze
    end
  end
end
