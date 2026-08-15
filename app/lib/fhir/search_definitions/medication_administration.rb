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
        "effective-time" => { type: :datetime, column: :effective_time },
        # 0..* references, so matched by jsonb containment rather than a column.
        # MedicationAdministration.partOf は「どの実施に伴う投与か」を指す
        # (放射線検査の造影剤)。参照先は Procedure に絞る(自身を束ねる用途は無い)。
        "part-of"        => { type: :reference, multiple: true, jsonb_key: "partOf",
                               ref_path: %w[reference], target_type: "Procedure" }
      }.freeze
    end
  end
end
