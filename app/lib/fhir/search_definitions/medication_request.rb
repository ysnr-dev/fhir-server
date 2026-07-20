module Fhir
  module SearchDefinitions
    module MedicationRequest
      PARAMS = {
        "identifier" => { type: :identifier },
        "status"     => { type: :token, column: :status },
        "intent"     => { type: :token, column: :intent },
        "subject"    => { type: :reference, column: :subject_reference,
                           target_type: "Patient", aliases: %w[patient] },
        "encounter"  => { type: :reference, column: :encounter_reference, target_type: "Encounter" },
        "requester"  => { type: :reference, column: :requester_reference, target_type: "Practitioner" },
        "code"       => { type: :token_or_text, token_column: :medication_code,
                           text_column: :medication_text },
        "authoredon" => { type: :datetime, column: :authored_on }
      }.freeze
    end
  end
end
