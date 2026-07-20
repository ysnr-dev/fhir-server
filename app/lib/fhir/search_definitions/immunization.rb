module Fhir
  module SearchDefinitions
    module Immunization
      # `date` searches occurrence[x]; only occurrenceDateTime is extracted.
      PARAMS = {
        "identifier"   => { type: :identifier },
        "status"       => { type: :token, column: :status },
        "vaccine-code" => { type: :token_or_text, token_column: :vaccine_code,
                             text_column: :vaccine_text },
        "patient"      => { type: :reference, column: :patient_reference, target_type: "Patient" },
        "date"         => { type: :datetime, column: :occurrence_time },
        "lot-number"   => { type: :string, column: :lot_number }
      }.freeze
    end
  end
end
