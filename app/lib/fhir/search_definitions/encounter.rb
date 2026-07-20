module Fhir
  module SearchDefinitions
    module Encounter
      PARAMS = {
        "identifier" => { type: :identifier },
        "status"     => { type: :token, column: :status },
        "class"      => { type: :token, column: :class_code },
        "subject"    => { type: :reference, column: :subject_reference,
                           target_type: "Patient", aliases: %w[patient] },
        "date"       => { type: :datetime, column: :period_start }
      }.freeze
    end
  end
end
