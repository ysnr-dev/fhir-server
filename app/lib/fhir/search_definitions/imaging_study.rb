module Fhir
  module SearchDefinitions
    module ImagingStudy
      PARAMS = {
        "identifier" => { type: :identifier },
        "status"     => { type: :token, column: :status },
        "modality"   => { type: :token, column: :modality_code },
        "subject"    => { type: :reference, column: :subject_reference,
                           target_type: "Patient", aliases: %w[patient] },
        "encounter"  => { type: :reference, column: :encounter_reference, target_type: "Encounter" },
        "started"    => { type: :datetime, column: :started }
      }.freeze
    end
  end
end
