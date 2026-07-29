module Fhir
  module SearchDefinitions
    module Questionnaire
      PARAMS = {
        "identifier"   => { type: :identifier },
        # R4 types these as uri and token respectively; `url` is matched exactly
        # so a canonical is never found by an accidental prefix.
        "url"          => { type: :uri, column: :url },
        "version"      => { type: :token, column: :version },
        "name"         => { type: :string, column: :name },
        "title"        => { type: :string, column: :title },
        "status"       => { type: :token, column: :status },
        "subject-type" => { type: :token, column: :subject_type },
        "publisher"    => { type: :string, column: :publisher },
        "code"         => { type: :token, column: :code_value },
        "date"         => { type: :datetime, column: :questionnaire_date }
      }.freeze
    end
  end
end
