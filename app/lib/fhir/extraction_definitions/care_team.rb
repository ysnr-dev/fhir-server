module Fhir
  module ExtractionDefinitions
    module CareTeam
      # status は primitive code。category は 0..* CodeableConcept(concept_list_code が
      # 先頭を取る)。managingOrganization は 0..* なので先頭の参照を列に持つ。
      FIELDS = {
        status: { path: "status" },
        category_code: { path: "category", transform: :concept_list_code },
        name: { path: "name" },
        subject_reference: { path: "subject.reference" },
        encounter_reference: { path: "encounter.reference" },
        managing_organization_reference: { path: "managingOrganization", transform: :first_reference },
        period_start: { path: "period.start", transform: :datetime },
        period_end: { path: "period.end", transform: :datetime }
      }.freeze

      TOKENS = {
        "status"   => { path: "status", kind: :code },
        "category" => { path: "category", kind: :codeable_concept_list }
      }.freeze
    end
  end
end
