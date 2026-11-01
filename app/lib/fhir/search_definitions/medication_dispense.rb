module Fhir
  module SearchDefinitions
    module MedicationDispense
      PARAMS = {
        "identifier"     => { type: :identifier },
        "status"         => { type: :token, column: :status },
        "subject"        => { type: :reference, column: :subject_reference,
                               target_type: "Patient", aliases: %w[patient] },
        "code"           => { type: :token_or_text, text_column: :medication_text },
        "context"        => { type: :reference, column: :context_reference, target_type: "Encounter" },
        # MedicationDispense.authorizingPrescription is a 0..* reference, so it is
        # matched by jsonb containment rather than an extracted column.
        "prescription"   => { type: :reference, multiple: true, jsonb_key: "authorizingPrescription",
                               ref_path: %w[reference], target_type: "MedicationRequest" },
        "whenhandedover" => { type: :datetime, column: :when_handed_over },
        # MedicationDispense.partOf は「どの行為に伴う払出か」を指す(輸血の出庫記録のハブ)。
        # MedicationAdministration の part-of と同じく参照先は Procedure に絞る。
        "part-of"        => { type: :reference, multiple: true, jsonb_key: "partOf",
                               ref_path: %w[reference], target_type: "Procedure" }
      }.freeze
    end
  end
end
