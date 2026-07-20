module Fhir
  module SearchDefinitions
    module ServiceRequest
      PARAMS = {
        "identifier" => { type: :identifier },
        "status"     => { type: :token, column: :status },
        "intent"     => { type: :token, column: :intent },
        "subject"    => { type: :reference, column: :subject_reference,
                           target_type: "Patient", aliases: %w[patient] },
        "code"       => { type: :token_or_text, token_column: :code,
                           text_column: :code_text },
        "authoredon" => { type: :datetime, column: :authored_on }
      }.freeze
    end
  end
end
