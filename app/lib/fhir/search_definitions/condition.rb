module Fhir
  module SearchDefinitions
    module Condition
      PARAMS = {
        "identifier"          => { type: :identifier },
        "clinical-status"     => { type: :token, column: :clinical_status },
        "verification-status" => { type: :token, column: :verification_status },
        "category"            => { type: :token, column: :category_code },
        "severity"            => { type: :token, column: :severity_code },
        "code"                => { type: :token_or_text, token_column: :code_value,
                                    text_column: :code_text },
        "subject"             => { type: :reference, column: :subject_reference,
                                    target_type: "Patient", aliases: %w[patient] },
        "encounter"           => { type: :reference, column: :encounter_reference, target_type: "Encounter" },
        "onset-date"          => { type: :datetime, column: :onset_time },
        "recorded-date"       => { type: :datetime, column: :recorded_time }
      }.freeze
    end
  end
end
