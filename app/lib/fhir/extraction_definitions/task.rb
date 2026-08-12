module Fhir
  module ExtractionDefinitions
    module Task
      # Task.for holds the beneficiary (the patient an order is being worked on
      # for); FHIR names its search param "subject", so the column is for_reference
      # but the param is "subject" (see SearchDefinitions::Task).
      # Task.basedOn / Task.partOf are 0..* references matched by jsonb containment
      # (see SearchDefinitions), so they have no extracted column here.
      FIELDS = {
        status: { path: "status" },
        intent: { path: "intent" },
        priority: { path: "priority" },
        business_status: { path: "businessStatus", transform: :coding_code },
        group_identifier: { path: "groupIdentifier.value" },
        performer_type: { path: "performerType", transform: :concept_list_code },
        code: { path: "code", transform: :coding_code },
        code_text: { path: "code", transform: :concept_text },
        for_reference: { path: "for.reference" },
        encounter_reference: { path: "encounter.reference" },
        requester_reference: { path: "requester.reference" },
        owner_reference: { path: "owner.reference" },
        focus_reference: { path: "focus.reference" },
        authored_on: { path: "authoredOn", transform: :datetime },
        last_modified: { path: "lastModified", transform: :datetime },
        execution_period_start: { path: "executionPeriod.start", transform: :datetime },
        execution_period_end: { path: "executionPeriod.end", transform: :datetime }
      }.freeze

      # groupIdentifier is an Identifier (0..1), not a coded element -- FHIR still
      # searches it as a token, so its (system, value) pair becomes one token row.
      TOKENS = {
        "status" => { path: "status", kind: :code },
        "intent" => { path: "intent", kind: :code },
        "priority" => { path: "priority", kind: :code },
        "business-status" => { path: "businessStatus", kind: :codeable_concept },
        "group-identifier" => { path: "groupIdentifier", kind: :identifier },
        "performer" => { path: "performerType", kind: :codeable_concept_list },
        "code" => { path: "code", kind: :codeable_concept }
      }.freeze
    end
  end
end
