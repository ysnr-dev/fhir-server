module Fhir
  module SearchDefinitions
    module Goal
      # `subject` は Patient を指す 1..1 の参照で、`patient` はその別名。target_type が
      # Patient の単一列参照なので、Goal は Fhir::PatientCompartment に自動で入り、
      # Patient/$everything に載る。
      #
      # 標準の target-date(Goal.target.dueDate)は定義しない -- target は 0..* の
      # backbone で、書き手も引く当ても無い。必要になったら nested_path で足す。
      PARAMS = {
        "identifier"         => { type: :identifier },
        "lifecycle-status"   => { type: :token, column: :lifecycle_status },
        "achievement-status" => { type: :token, column: :achievement_status },
        # Goal.category は 0..* CodeableConcept。CarePlan.category と同じ理由で
        # 平坦化した列は持たず resource_tokens だけで突き合わせる。
        "category"           => { type: :token },
        "subject"            => { type: :reference, column: :subject_reference,
                                   target_type: "Patient", aliases: %w[patient] },
        # Goal.startDate は日付そのもの(タイムゾーンを持たない)なので :date。
        "start-date"         => { type: :date, column: :start_date }
      }.freeze
    end
  end
end
