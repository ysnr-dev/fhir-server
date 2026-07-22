module Fhir
  module SearchDefinitions
    module DocumentReference
      PARAMS = {
        "identifier" => { type: :identifier },
        "status"     => { type: :token, column: :status },
        "type"       => { type: :token_or_text, token_column: :type_code, text_column: :type_text },
        "subject"    => { type: :reference, column: :subject_reference,
                           target_type: "Patient", aliases: %w[patient] },
        "date"       => { type: :datetime, column: :document_date }
      }.freeze
    end
  end
end
