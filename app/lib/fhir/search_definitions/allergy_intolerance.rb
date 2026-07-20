module Fhir
  module SearchDefinitions
    module AllergyIntolerance
      # `date` is the standard R4 search parameter over recordedDate.
      PARAMS = {
        "identifier"          => { type: :identifier },
        "clinical-status"     => { type: :token, column: :clinical_status },
        "verification-status" => { type: :token, column: :verification_status },
        "type"                => { type: :token, column: :type_code },
        "category"            => { type: :token, column: :category_code },
        "criticality"         => { type: :token, column: :criticality },
        "code"                => { type: :token_or_text, token_column: :code_value,
                                    text_column: :code_text },
        "patient"             => { type: :reference, column: :patient_reference, target_type: "Patient" },
        "date"                => { type: :datetime, column: :recorded_time }
      }.freeze
    end
  end
end
