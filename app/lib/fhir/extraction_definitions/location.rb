module Fhir
  module ExtractionDefinitions
    module Location
      FIELDS = {
        status: { path: "status" },
        name: { path: "name" },
        address_text: { path: "address", transform: :address_text },
        type_code: { path: "type", transform: :concept_list_code },
        organization_reference: { path: "managingOrganization.reference" },
        partof_reference: { path: "partOf.reference" }
      }.freeze

      TOKENS = {
        "status" => { path: "status", kind: :code },
        "type"   => { path: "type", kind: :codeable_concept_list }
      }.freeze
    end
  end
end
