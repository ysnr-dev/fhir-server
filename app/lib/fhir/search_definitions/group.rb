module Fhir
  module SearchDefinitions
    module Group
      PARAMS = {
        "identifier"      => { type: :identifier },
        "type"            => { type: :token, column: :group_type },
        "code"            => { type: :token, column: :code_value },
        "actual"          => { type: :boolean, column: :actual },
        "managing-entity" => { type: :reference, column: :managing_entity_reference,
                                target_type: "Organization" },
        # member is 0..* Reference(Patient|Practitioner|PractitionerRole|Device|...),
        # matched by jsonb containment rather than an extracted column. Being
        # multi-valued, it gives Group no patient-compartment membership even
        # though it targets Patient -- see Fhir::PatientCompartment.
        "member"          => { type: :reference, multiple: true, jsonb_key: "member",
                                ref_path: %w[entity reference], target_type: "Patient" }
      }.freeze
    end
  end
end
