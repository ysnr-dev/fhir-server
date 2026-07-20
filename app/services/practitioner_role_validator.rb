class PractitionerRoleValidator
  Result = Struct.new(:errors, :warnings) do
    def valid?
      errors.empty?
    end

    def issues
      errors.map { |e| e.merge(severity: "error") } +
        warnings.map { |w| w.merge(severity: "warning") }
    end
  end

  def self.call(payload)
    new(payload).call
  end

  def initialize(payload)
    @payload = payload
  end

  # JP Core defines no required top-level elements for PractitionerRole; validation
  # is limited to type-checking the optional `active` flag.
  def call
    errors = []
    warnings = []

    validate_active(errors)

    Result.new(errors, warnings)
  end

  private

  attr_reader :payload

  def validate_active(errors)
    return unless payload.key?("active")

    active = payload["active"]
    return if active.is_a?(TrueClass) || active.is_a?(FalseClass)

    errors << {
      code: "value",
      diagnostics: "PractitionerRole.active must be a boolean",
      expression: ["PractitionerRole.active"]
    }
  end
end
