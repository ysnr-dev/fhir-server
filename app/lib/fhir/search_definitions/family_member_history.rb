module Fhir
  module SearchDefinitions
    module FamilyMemberHistory
      # `patient` は Patient を指す 1..1 の単一列参照なので、FamilyMemberHistory は
      # Fhir::PatientCompartment に自動で入り、Patient/$everything に載る。
      # `code` は condition[].code(家族の病名)。JP Core の例のように text だけで
      # 書かれることが多いので、コードとテキストの両方で引けるようにしている。
      # テキスト側は全 condition の病名を連結した列への前方一致なので、2 件目以降の
      # 病名を引くには `code:contains` を使う(コードはどの condition でも一致する)。
      # `date` は記録日(FamilyMemberHistory.date)。
      PARAMS = {
        "identifier"   => { type: :identifier },
        "status"       => { type: :token, column: :status },
        "relationship" => { type: :token, column: :relationship_code },
        "sex"          => { type: :token, column: :sex_code },
        "code"         => { type: :token_or_text, text_column: :code_text },
        "patient"      => { type: :reference, column: :patient_reference, target_type: "Patient" },
        "date"         => { type: :datetime, column: :recorded_time }
      }.freeze
    end
  end
end
