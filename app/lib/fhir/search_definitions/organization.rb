module Fhir
  module SearchDefinitions
    module Organization
      PARAMS = {
        "identifier" => { type: :identifier },
        "name"       => { type: :string, column: :name },
        "active"     => { type: :boolean, column: :active }
      }.freeze
    end
  end
end
