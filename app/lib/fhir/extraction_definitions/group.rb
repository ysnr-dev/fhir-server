module Fhir
  module ExtractionDefinitions
    module Group
      # Group.type is a primitive code (not a Coding), so it needs no transform.
      # The column is group_type because a column named `type` would activate
      # Rails single-table inheritance -- see the migration.
      # characteristic is 0..* with its searchable code under the repeating
      # element, which a dot path cannot fan out over, so it is not extracted.
      FIELDS = {
        group_type: { path: "type" },
        actual: { path: "actual" },
        code_value: { path: "code", transform: :coding_code },
        managing_entity_reference: { path: "managingEntity.reference" }
      }.freeze

      TOKENS = {
        "type" => { path: "type", kind: :code },
        "code" => { path: "code", kind: :codeable_concept }
      }.freeze
    end
  end
end
