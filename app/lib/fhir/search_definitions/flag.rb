module Fhir
  module SearchDefinitions
    module Flag
      # `subject` は Patient を指す 1..1 の参照で、`patient` はその別名(Condition と
      # 同じ扱い)。target_type が Patient の単一列参照なので、Flag は
      # Fhir::PatientCompartment に自動で入り、Patient/$everything に載る。
      PARAMS = {
        "identifier" => { type: :identifier },
        "status"     => { type: :token, column: :status },
        "category"   => { type: :token, column: :category_code },
        "code"       => { type: :token_or_text, token_column: :code_value,
                           text_column: :code_text },
        "subject"    => { type: :reference, column: :subject_reference,
                           target_type: "Patient", aliases: %w[patient] },
        "encounter"  => { type: :reference, column: :encounter_reference, target_type: "Encounter" },
        "author"     => { type: :reference, column: :author_reference, target_type: "Practitioner" },
        # eq は仕様どおりの包含(検索区間が period を完全に含む)。period.end が
        # NULL なら「まだ継続中」を意味する(Encounter.date と同じ)。
        "date"       => { type: :datetime, column: :period_start, end_column: :period_end }
      }.freeze
    end
  end
end
