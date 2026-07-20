module Fhir
  module SearchDefinitions
    module Medication
      PARAMS = {
        "identifier"   => { type: :identifier },
        "status"       => { type: :token, column: :status },
        "code"         => { type: :token_or_text, token_column: :medication_code,
                             text_column: :medication_text },
        "form"         => { type: :token, column: :form_code },
        "manufacturer" => { type: :reference, column: :manufacturer_reference, target_type: "Organization" }
      }.freeze
    end
  end
end
