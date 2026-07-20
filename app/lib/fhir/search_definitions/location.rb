module Fhir
  module SearchDefinitions
    module Location
      PARAMS = {
        "identifier"   => { type: :identifier },
        "name"         => { type: :string, column: :name },
        "address"      => { type: :string, column: :address_text },
        "status"       => { type: :token, column: :status },
        "type"         => { type: :token, column: :type_code },
        "organization" => { type: :reference, column: :organization_reference, target_type: "Organization" }
      }.freeze
    end
  end
end
