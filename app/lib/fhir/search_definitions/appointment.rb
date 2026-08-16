module Fhir
  module SearchDefinitions
    module Appointment
      PARAMS = {
        "identifier" => { type: :identifier },
        "status" => { type: :token, column: :status },
        "appointment-type" => { type: :token, column: :appointment_type },
        # 0..* CodeableConcept。理由は SearchDefinitions::Schedule を参照。
        "service-category" => { type: :token },
        "service-type" => { type: :token },
        "specialty" => { type: :token },
        "reason-code" => { type: :token },
        # Appointment.participant[].status(accepted / declined / tentative /
        # needs-action)。「患者の承諾待ちの予約」を引くのに使う。
        "part-status" => { type: :token },
        # Appointment.participant[].actor のうち Patient を指すもの。0..* の
        # participant から 1 件を平坦化した列で持つ理由は
        # ExtractionDefinitions::Appointment を参照(患者コンパートメントと
        # チェーン検索・_has がカラムを前提にしている)。
        "patient" => { type: :reference, column: :patient_reference, target_type: "Patient" },
        # actor は participant の参照先すべて。practitioner はその別名で、
        # location は同じ配列を Location 既定で引くための別定義。
        "actor" => { type: :reference, multiple: true, jsonb_key: "participant",
                      ref_path: %w[actor reference], target_type: "Practitioner",
                      aliases: %w[practitioner] },
        "location" => { type: :reference, multiple: true, jsonb_key: "participant",
                         ref_path: %w[actor reference], target_type: "Location" },
        # 押さえた枠。枠側から見る場合は _revinclude=Appointment:slot。
        "slot" => { type: :reference, multiple: true, jsonb_key: "slot",
                     ref_path: %w[reference], target_type: "Slot" },
        # この予約を生んだ依頼(紹介・再診指示)。
        "based-on" => { type: :reference, multiple: true, jsonb_key: "basedOn",
                         ref_path: %w[reference], target_type: "ServiceRequest" },
        # 予約の理由。R4 の参照先は Condition|Procedure|Observation|
        # ImmunizationRecommendation だが、書かれているのは Condition だけなので
        # 既定の参照先はそれに絞る(ServiceRequest.reason-reference と同じ扱い)。
        "reason-reference" => { type: :reference, multiple: true, jsonb_key: "reasonReference",
                                 ref_path: %w[reference], target_type: "Condition" },
        # R4 の date は Appointment.start(期間ではない)。「その日の予約」は
        # date=ge…&date=lt… の AND で表す。
        "date" => { type: :datetime, column: :start_time }
      }.freeze
    end
  end
end
