module Fhir
  # Feature switch for StructureDefinition-based profile validation against the
  # vendored Implementation Guides (Fhir::Profile::DefinitionStore), separate
  # from the per-resource hand validators (PatientValidator etc.) which always
  # run regardless of this setting.
  #
  #   off     - the profile engine never runs (hand validators only).
  #   warn    - the default. $validate reports every profile issue at its
  #             intrinsic severity, but create/update/patch are never blocked
  #             by profile violations (only the hand validators can 422).
  #             Violations on a successful write are logged, not rejected --
  #             existing client data may predate this engine.
  #   enforce - profile violations also 422 on create/update/patch, merged
  #             into the same OperationOutcome as the hand validator's issues.
  # Which profiles get checked is not a question this module answers: it is
  # decided per URL by DefinitionStore.known_profile?, i.e. by whether some
  # vendored IG actually ships the definition.
  module Profile
    mattr_accessor :mode, default: ENV.fetch("FHIR_PROFILE_VALIDATION", "warn").to_sym

    def self.off?
      mode == :off
    end

    def self.warn?
      mode == :warn
    end

    def self.enforce?
      mode == :enforce
    end
  end
end
