module Fhir
  module SearchDefinitions
    module Patient
      PARAMS = {
        "identifier" => { type: :identifier },
        "name"       => { type: :string, column: :name_text, word_boundary: true },
        "family"     => { type: :string, column: :family },
        "given"      => { type: :string, column: :given, word_boundary: true },
        # address_text / phone_digits hold every address / phone number space-joined,
        # hence word_boundary. phone is a token in the FHIR spec (exact match), but
        # numbers are written with and without hyphens, so it is searched as a string
        # over the digits only (the query value is reduced to digits too).
        "address"    => { type: :string, column: :address_text, word_boundary: true },
        "phone"      => { type: :string, column: :phone_digits, word_boundary: true, digits_only: true },
        "gender"     => { type: :token, column: :gender },
        "birthdate"  => { type: :date, column: :birth_date },
        "active"     => { type: :boolean, column: :active }
      }.freeze
    end
  end
end
