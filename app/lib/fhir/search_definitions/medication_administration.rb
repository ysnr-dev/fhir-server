module Fhir
  module SearchDefinitions
    module MedicationAdministration
      PARAMS = {
        "identifier"     => { type: :identifier },
        "status"         => { type: :token, column: :status },
        "subject"        => { type: :reference, column: :subject_reference,
                               target_type: "Patient", aliases: %w[patient] },
        "code"           => { type: :token_or_text, token_column: :medication_code,
                               text_column: :medication_text },
        "context"        => { type: :reference, column: :context_reference, target_type: "Encounter" },
        "request"        => { type: :reference, column: :request_reference, target_type: "MedicationRequest" },
        "effective-time" => { type: :datetime, column: :effective_time }
      }.freeze
    end
  end
end
