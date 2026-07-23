module Fhir
  module SearchDefinitions
    module Composition
      PARAMS = {
        "identifier" => { type: :identifier },
        "status"     => { type: :token, column: :status },
        "type"       => { type: :token_or_text, token_column: :type_code, text_column: :type_text },
        "category"   => { type: :token, column: :category_code },
        "subject"    => { type: :reference, column: :subject_reference,
                           target_type: "Patient", aliases: %w[patient] },
        "encounter"  => { type: :reference, column: :encounter_reference, target_type: "Encounter" },
        # Composition.author is 0..* references, so it is matched by jsonb
        # containment rather than an extracted column.
        "author"     => { type: :reference, multiple: true, jsonb_key: "author",
                           ref_path: %w[reference], target_type: "Practitioner" },
        "date"       => { type: :datetime, column: :composition_date }
      }.freeze
    end
  end
end
