module Fhir
  module SearchDefinitions
    module Coverage
      PARAMS = {
        "identifier"  => { type: :identifier },
        "status"      => { type: :token, column: :status },
        "type"        => { type: :token_or_text, token_column: :type_code,
                            text_column: :type_text },
        "beneficiary" => { type: :reference, column: :beneficiary_reference,
                            target_type: "Patient", aliases: %w[patient] },
        # payor is 1..* reference living only in content; matched via jsonb containment.
        "payor"       => { type: :reference, multiple: true, jsonb_key: "payor",
                            ref_path: %w[reference], target_type: "Organization" },
        "dependent"   => { type: :string, column: :dependent }
      }.freeze
    end
  end
end
