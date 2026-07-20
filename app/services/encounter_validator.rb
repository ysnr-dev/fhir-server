class EncounterValidator
  Result = Struct.new(:errors, :warnings) do
    def valid?
      errors.empty?
    end

    def issues
      errors.map { |e| e.merge(severity: "error") } +
        warnings.map { |w| w.merge(severity: "warning") }
    end
  end

  VALID_STATUSES = %w[planned arrived triaged in-progress onleave finished cancelled entered-in-error unknown].freeze

  def self.call(payload)
    new(payload).call
  end

  def initialize(payload)
    @payload = payload
  end

  def call
    errors = []
    warnings = []

    validate_status(errors)
    validate_class(errors)

    Result.new(errors, warnings)
  end

  private

  attr_reader :payload

  def validate_status(errors)
    status = payload["status"]

    if status.blank?
      errors << {
        code: "required",
        diagnostics: "Encounter.status is required",
        expression: ["Encounter.status"]
      }
      return
    end

    return if VALID_STATUSES.include?(status)

    errors << {
      code: "value",
      diagnostics: "Invalid Encounter.status '#{status}'. Must be one of: #{VALID_STATUSES.join(', ')}",
      expression: ["Encounter.status"]
    }
  end

  # class is 1..1. Its binding to v3 ActEncounterCode is extensible, so the code
  # value is not constrained here -- only that a class coding with a code is present.
  def validate_class(errors)
    return if payload.dig("class", "code").present?

    errors << {
      code: "required",
      diagnostics: "Encounter.class is required",
      expression: ["Encounter.class"]
    }
  end
end
