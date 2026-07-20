class LocationValidator
  Result = Struct.new(:errors, :warnings) do
    def valid?
      errors.empty?
    end

    def issues
      errors.map { |e| e.merge(severity: "error") } +
        warnings.map { |w| w.merge(severity: "warning") }
    end
  end

  VALID_STATUSES = %w[active suspended inactive].freeze
  VALID_MODES = %w[instance kind].freeze

  def self.call(payload)
    new(payload).call
  end

  def initialize(payload)
    @payload = payload
  end

  # JP Core defines no required top-level elements for Location; status and mode
  # are optional but carry required value-set bindings when present.
  def call
    errors = []
    warnings = []

    validate_coded(errors, "status", VALID_STATUSES)
    validate_coded(errors, "mode", VALID_MODES)

    Result.new(errors, warnings)
  end

  private

  attr_reader :payload

  def validate_coded(errors, field, allowed)
    value = payload[field]
    return if value.blank?
    return if allowed.include?(value)

    errors << {
      code: "value",
      diagnostics: "Invalid Location.#{field} '#{value}'. Must be one of: #{allowed.join(', ')}",
      expression: ["Location.#{field}"]
    }
  end
end
