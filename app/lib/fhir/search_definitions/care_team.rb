module Fhir
  module SearchDefinitions
    module CareTeam
      # `subject` は 0..1 の Patient 参照。組織的なチーム(NST・ICT など、患者を持たない
      # チーム)は subject が無く、どの患者コンパートメントにも入らない。`participant` は
      # 0..* の participant[].member を平坦化した jsonb 検索(Appointment.actor と同じ)。
      PARAMS = {
        "identifier" => { type: :identifier },
        "status"     => { type: :token, column: :status },
        "category"   => { type: :token, column: :category_code },
        "name"       => { type: :string, column: :name },
        "subject"    => { type: :reference, column: :subject_reference,
                           target_type: "Patient", aliases: %w[patient] },
        "encounter"  => { type: :reference, column: :encounter_reference, target_type: "Encounter" },
        "participant" => { type: :reference, multiple: true, jsonb_key: "participant",
                            ref_path: %w[member reference], target_type: "Practitioner" },
        "managing-organization" => { type: :reference, column: :managing_organization_reference,
                                     target_type: "Organization" },
        "date"       => { type: :datetime, column: :period_start, end_column: :period_end }
      }.freeze
    end
  end
end
