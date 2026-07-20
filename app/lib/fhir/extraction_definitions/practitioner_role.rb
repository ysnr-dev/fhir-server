module Fhir
  module ExtractionDefinitions
    module PractitionerRole
      FIELDS = {
        active: { path: "active" },
        practitioner_reference: { path: "practitioner.reference" },
        organization_reference: { path: "organization.reference" },
        role_code: { path: "code", transform: :concept_list_code },
        specialty_code: { path: "specialty", transform: :concept_list_code }
      }.freeze
    end
  end
end
