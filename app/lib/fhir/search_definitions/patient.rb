module Fhir
  module SearchDefinitions
    module Patient
      PARAMS = {
        "identifier" => { type: :identifier },
        "name"       => { type: :string, column: :name_text },
        "family"     => { type: :string, column: :family },
        "given"      => { type: :string, column: :given },
        "gender"     => { type: :token, column: :gender },
        "birthdate"  => { type: :date, column: :birth_date },
        "active"     => { type: :boolean, column: :active }
      }.freeze
    end
  end
end
