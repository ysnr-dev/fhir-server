module Fhir
  # Allow-list of the reference search parameters that `_include` / `_revinclude`
  # may traverse, keyed by "SourceType" then search parameter name. Only the
  # entries listed here are honored; anything else is ignored (per the FHIR spec,
  # a server may silently drop unsupported include parameters).
  #
  # Each definition describes how to read the reference out of the source's FHIR
  # `content`. Single-valued (0..1) and multi-valued (0..*) references use
  # different keys:
  #   targets   - resource types the reference is allowed to point at
  #   alias     - name of another param in the same source whose definition to use
  #
  #   single-valued:
  #     path    - keys to dig the reference string ("Type/id") out of `content`
  #     column  - extracted search column, used for indexed reverse lookups
  #
  #   multi-valued (multiple: true):
  #     jsonb_key - the `content` array key holding the repeating element
  #     ref_path  - keys from each array element down to the reference string;
  #                 used both to read refs (forward) and to build the jsonb
  #                 containment query (reverse), GIN-indexed on `content`
  module SearchReferences
    MAP = {
      "Encounter" => {
        "subject" => { path: %w[subject reference], targets: %w[Patient], column: "subject_reference" },
        "patient" => { alias: "subject" },
        "service-provider" => { path: %w[serviceProvider reference], targets: %w[Organization], column: "service_provider_reference" },
        "location" => { multiple: true, jsonb_key: "location", ref_path: %w[location reference], targets: %w[Location] },
        "participant" => { multiple: true, jsonb_key: "participant", ref_path: %w[individual reference], targets: %w[Practitioner PractitionerRole] },
        "practitioner" => { alias: "participant" }
      },
      "MedicationRequest" => {
        "subject" => { path: %w[subject reference], targets: %w[Patient], column: "subject_reference" },
        "patient" => { alias: "subject" },
        "encounter" => { path: %w[encounter reference], targets: %w[Encounter], column: "encounter_reference" },
        "requester" => { path: %w[requester reference], targets: %w[Practitioner PractitionerRole Organization], column: "requester_reference" },
        "based-on" => { multiple: true, jsonb_key: "basedOn", ref_path: %w[reference], targets: %w[ServiceRequest] }
      },
      "Medication" => {
        "manufacturer" => { path: %w[manufacturer reference], targets: %w[Organization], column: "manufacturer_reference" }
      },
      "MedicationDispense" => {
        "subject" => { path: %w[subject reference], targets: %w[Patient], column: "subject_reference" },
        "patient" => { alias: "subject" },
        "context" => { path: %w[context reference], targets: %w[Encounter], column: "context_reference" },
        "prescription" => { multiple: true, jsonb_key: "authorizingPrescription", ref_path: %w[reference], targets: %w[MedicationRequest] }
      },
      "MedicationAdministration" => {
        "subject" => { path: %w[subject reference], targets: %w[Patient], column: "subject_reference" },
        "patient" => { alias: "subject" },
        "context" => { path: %w[context reference], targets: %w[Encounter], column: "context_reference" },
        "request" => { path: %w[request reference], targets: %w[MedicationRequest], column: "request_reference" }
      },
      "MedicationStatement" => {
        "subject" => { path: %w[subject reference], targets: %w[Patient], column: "subject_reference" },
        "patient" => { alias: "subject" },
        "context" => { path: %w[context reference], targets: %w[Encounter], column: "context_reference" }
      },
      "ServiceRequest" => {
        "subject" => { path: %w[subject reference], targets: %w[Patient], column: "subject_reference" },
        "patient" => { alias: "subject" },
        "encounter" => { path: %w[encounter reference], targets: %w[Encounter], column: "encounter_reference" },
        "requester" => { path: %w[requester reference], targets: %w[Practitioner PractitionerRole Organization], column: "requester_reference" }
      },
      "PractitionerRole" => {
        "practitioner" => { path: %w[practitioner reference], targets: %w[Practitioner], column: "practitioner_reference" },
        "organization" => { path: %w[organization reference], targets: %w[Organization], column: "organization_reference" }
      },
      "Location" => {
        "organization" => { path: %w[managingOrganization reference], targets: %w[Organization], column: "organization_reference" },
        "partof" => { path: %w[partOf reference], targets: %w[Location], column: "partof_reference" }
      },
      "Organization" => {
        "partof" => { path: %w[partOf reference], targets: %w[Organization], column: "partof_reference" }
      }
    }.freeze

    module_function

    # Parses an `_include`/`_revinclude` token of the form "Source:param" or
    # "Source:param:TargetType" and resolves it against the allow-list.
    # Returns { source_type:, param:, definition:, target_type: } or nil when the
    # token is unknown/unsupported (caller ignores nil).
    def lookup(token)
      return nil if token.blank?

      source_type, param, target_type = token.split(":", 3)
      return nil if source_type.blank? || param.blank?

      params_map = MAP[source_type]
      return nil unless params_map

      definition = params_map[param]
      return nil unless definition

      # Resolve aliases (e.g. "patient" -> "subject") to the canonical definition.
      if definition[:alias]
        param = definition[:alias]
        definition = params_map[param]
        return nil unless definition
      end

      # An optional third segment constrains the target type; reject if not allowed.
      return nil if target_type.present? && !definition[:targets].include?(target_type)

      {
        source_type: source_type,
        param: param,
        definition: definition,
        target_type: target_type.presence
      }
    end
  end
end
