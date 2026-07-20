module Fhir
  module SearchDefinitions
    module DiagnosticReport
      PARAMS = {
        "identifier" => { type: :identifier },
        "status"     => { type: :token, column: :status },
        "category"   => { type: :token, column: :category_code },
        "code"       => { type: :token_or_text, token_column: :code_value,
                           text_column: :code_text },
        "subject"    => { type: :reference, column: :subject_reference,
                           target_type: "Patient", aliases: %w[patient] },
        "encounter"  => { type: :reference, column: :encounter_reference, target_type: "Encounter" },
        "date"       => { type: :datetime, column: :effective_time },
        # result (Observation) and specimen (Specimen) are 0..* references, so they
        # are matched by jsonb containment rather than an extracted column.
        "result"     => { type: :reference, multiple: true, jsonb_key: "result",
                           ref_path: %w[reference], target_type: "Observation" },
        "specimen"   => { type: :reference, multiple: true, jsonb_key: "specimen",
                           ref_path: %w[reference], target_type: "Specimen" }
      }.freeze
    end
  end
end
