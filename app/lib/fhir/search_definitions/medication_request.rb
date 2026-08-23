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
        "authoredon" => { type: :datetime, column: :authored_on },
        # 0..* references, so matched by jsonb containment rather than a column.
        # MedicationRequest.basedOn は処方オーダー(ServiceRequest ヘッダ)を指す。
        # 処方箋の明細取得やオーダー単位のカスケード削除が
        # `MedicationRequest?based-on=ServiceRequest/X` で 1 検索になる
        # (_revinclude 側は SearchReferences に定義済み)。
        "based-on"   => { type: :reference, multiple: true, jsonb_key: "basedOn",
                           ref_path: %w[reference], target_type: "ServiceRequest" }
      }.freeze
    end
  end
end
