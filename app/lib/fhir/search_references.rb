module Fhir
  # Allow-list of the reference search parameters that `_include` / `_revinclude`
  # may traverse, keyed by "SourceType" then search parameter name. Only the
  # entries listed here are honored; anything else is ignored (per the FHIR spec,
  # a server may silently drop unsupported include parameters).
  #
  # Each definition describes how to read the reference out of the source's FHIR
  # `content`:
  #   path      - keys to dig the reference string ("Type/id") out of `content`
  #   multiple  - true when the reference element is an array (0..*)
  #   targets   - resource types the reference is allowed to point at
  #   jsonb_key - top-level `content` key, used for jsonb containment queries
  #   column    - extracted search column (single-valued refs only), used for
  #               indexed reverse lookups instead of a jsonb query
  module SearchReferences
    MAP = {
      "ServiceRequest" => {
        "subject" => { path: %w[subject reference], multiple: false, targets: %w[Patient], jsonb_key: "subject", column: "subject_reference" },
        "patient" => { alias: "subject" }
      },
      "MedicationRequest" => {
        "subject" => { path: %w[subject reference], multiple: false, targets: %w[Patient], jsonb_key: "subject", column: "subject_reference" },
        "patient" => { alias: "subject" },
        "based-on" => { path: %w[basedOn reference], multiple: true, targets: %w[ServiceRequest], jsonb_key: "basedOn" }
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
