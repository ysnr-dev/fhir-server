module Fhir
  # Feature switch for JP Core StructureDefinition-based profile validation
  # (Fhir::Profile::Validator), separate from the per-resource hand validators
  # (PatientValidator etc.) which always run regardless of this setting.
  #
  #   off     - the profile engine never runs (hand validators only).
  #   warn    - the default. $validate reports every profile issue at its
  #             intrinsic severity, but create/update/patch are never blocked
  #             by profile violations (only the hand validators can 422).
  #             Violations on a successful write are logged, not rejected --
  #             existing client data may predate this engine.
  #   enforce - profile violations also 422 on create/update/patch, merged
  #             into the same OperationOutcome as the hand validator's issues.
  module Profile
    # Single source of truth for "is this a JP Core canonical URL" -- shared
    # by lib/tasks/jp_core.rake (closure traversal), Validator (nested-profile
    # recursion), and Operation (deciding whether a registry profile has a
    # vendored definition at all).
    JP_CORE_PREFIX = "http://jpfhir.jp/fhir/core/".freeze

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

    def self.jp_core_profile?(url)
      url.to_s.start_with?(JP_CORE_PREFIX)
    end
  end
end
