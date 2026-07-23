module Fhir
  module ExtractionDefinitions
    module AllergyIntolerance
      # type / criticality are primitive codes (raw dig). category is 0..* of primitive
      # codes (first_value takes the first). recordedDate feeds the `date` search param.
      FIELDS = {
        clinical_status: { path: "clinicalStatus", transform: :coding_code },
        verification_status: { path: "verificationStatus", transform: :coding_code },
        type_code: { path: "type" },
        category_code: { path: "category", transform: :first_value },
        criticality: { path: "criticality" },
        code_value: { path: "code", transform: :coding_code },
        code_text: { path: "code", transform: :concept_text },
        patient_reference: { path: "patient.reference" },
        recorded_time: { path: "recordedDate", transform: :datetime }
      }.freeze

      # Token search sources (resource_tokens), keyed by canonical search-param name.
      TOKENS = {
        "clinical-status"     => { path: "clinicalStatus", kind: :codeable_concept },
        "verification-status" => { path: "verificationStatus", kind: :codeable_concept },
        "type"                => { path: "type", kind: :code },
        "category"            => { path: "category", kind: :code_list },
        "criticality"         => { path: "criticality", kind: :code },
        "code"                => { path: "code", kind: :codeable_concept }
      }.freeze
    end
  end
end
