class PractitionerValidator
  Result = Struct.new(:errors, :warnings) do
    def valid?
      errors.empty?
    end

    def issues
      errors.map { |e| e.merge(severity: "error") } +
        warnings.map { |w| w.merge(severity: "warning") }
    end
  end

  VALID_GENDERS = %w[male female other unknown].freeze
  DATE_FORMATS = [
    /\A\d{4}\z/,                     # YYYY
    /\A\d{4}-\d{2}\z/,                # YYYY-MM
    /\A\d{4}-\d{2}-\d{2}\z/           # YYYY-MM-DD
  ].freeze

  def self.call(payload)
    new(payload).call
  end

  def initialize(payload)
    @payload = payload
  end

  # JP Core has no truly required top-level elements for Practitioner
  # (qualification.code is 1..1 only when qualification is present at all).
  def call
    errors = []
    warnings = []

    validate_gender(errors)
    validate_birth_date(errors)

    Result.new(errors, warnings)
  end

  private

  attr_reader :payload

  def validate_gender(errors)
    gender = payload["gender"]
    return if gender.nil?

    return if VALID_GENDERS.include?(gender)

    errors << {
      code: "value",
      diagnostics: "Invalid Practitioner.gender '#{gender}'. Must be one of: #{VALID_GENDERS.join(', ')}",
      expression: ["Practitioner.gender"]
    }
  end

  def validate_birth_date(errors)
    birth_date = payload["birthDate"]
    return if birth_date.nil?

    unless birth_date.is_a?(String) && DATE_FORMATS.any? { |fmt| birth_date.match?(fmt) }
      errors << {
        code: "value",
        diagnostics: "Invalid Practitioner.birthDate '#{birth_date}'. Expected format YYYY, YYYY-MM, or YYYY-MM-DD",
        expression: ["Practitioner.birthDate"]
      }
      return
    end

    Date.iso8601(pad_partial_date(birth_date))
  rescue ArgumentError
    errors << {
      code: "value",
      diagnostics: "Invalid Practitioner.birthDate '#{birth_date}': not a real calendar date",
      expression: ["Practitioner.birthDate"]
    }
  end

  def pad_partial_date(date)
    case date
    when /\A\d{4}\z/ then "#{date}-01-01"
    when /\A\d{4}-\d{2}\z/ then "#{date}-01"
    else date
    end
  end
end
