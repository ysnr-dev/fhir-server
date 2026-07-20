module Fhir
  module SearchDefinitions
    module PractitionerRole
      PARAMS = {
        "identifier"   => { type: :identifier },
        "practitioner" => { type: :reference, column: :practitioner_reference, target_type: "Practitioner" },
        "organization" => { type: :reference, column: :organization_reference, target_type: "Organization" },
        "role"         => { type: :token, column: :role_code },
        "specialty"    => { type: :token, column: :specialty_code },
        "active"       => { type: :boolean, column: :active }
      }.freeze
    end
  end
end
