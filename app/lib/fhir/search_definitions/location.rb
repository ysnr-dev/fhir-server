module Fhir
  module SearchDefinitions
    module Location
      PARAMS = {
        "identifier"   => { type: :identifier },
        "name"         => { type: :string, column: :name },
        # address_text is a flattened line/city/state/postalCode column (see
        # Location#sync_search_fields!), so a plain prefix match would only ever
        # match the first token.
        "address"      => { type: :string, column: :address_text, word_boundary: true },
        "status"       => { type: :token, column: :status },
        "type"         => { type: :token, column: :type_code },
        "organization" => { type: :reference, column: :organization_reference, target_type: "Organization" },
        "partof"       => { type: :reference, column: :partof_reference, target_type: "Location" }
      }.freeze
    end
  end
end
