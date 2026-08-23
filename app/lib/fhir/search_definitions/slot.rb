module Fhir
  module SearchDefinitions
    module Slot
      PARAMS = {
        "identifier" => { type: :identifier },
        # 空き枠は status=free。busy-tentative は仮押さえ(Appointment.status=pending)。
        "status" => { type: :token, column: :status },
        # Slot.schedule は 1..1 必須。予約画面は schedule + status + start で引く。
        "schedule" => { type: :reference, column: :schedule_reference, target_type: "Schedule" },
        # R4 が Slot に定める日時パラメータは start だけ。「9 時〜12 時の空き枠」は
        # start=ge…&start=lt… の AND で表せるが、それだと期間の頭をまたぐ枠
        # (開始が範囲より前で終了が範囲内)を取りこぼす。end は R4 に定義が無い
        # ローカル追加で、範囲に掛かる枠を start=lt…&end=gt… で正確に引ける。
        "start" => { type: :datetime, column: :start_time },
        "end" => { type: :datetime, column: :end_time },
        "appointment-type" => { type: :token, column: :appointment_type },
        # 0..* CodeableConcept。理由は SearchDefinitions::Schedule を参照。
        "service-category" => { type: :token },
        "service-type" => { type: :token },
        "specialty" => { type: :token }
      }.freeze
    end
  end
end
