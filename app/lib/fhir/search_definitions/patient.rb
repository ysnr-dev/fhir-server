module Fhir
  module SearchDefinitions
    module Patient
      PARAMS = {
        "identifier" => { type: :identifier },
        # name_text/given are space-joined multi-token columns (see Patient#sync_search_fields!),
        # so a plain prefix match would only ever match the first token.
        "name"       => { type: :string, column: :name_text, word_boundary: true },
        "family"     => { type: :string, column: :family },
        "given"      => { type: :string, column: :given, word_boundary: true },
        "gender"     => { type: :token, column: :gender },
        "birthdate"  => { type: :date, column: :birth_date },
        "active"     => { type: :boolean, column: :active }
      }.freeze
    end
  end
end
