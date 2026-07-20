module Fhir
  module SearchDefinitions
    module Organization
      PARAMS = {
        "identifier" => { type: :identifier },
        "name"       => { type: :string, column: :name },
        "active"     => { type: :boolean, column: :active },
        "partof"     => { type: :reference, column: :partof_reference, target_type: "Organization" }
      }.freeze
    end
  end
end
