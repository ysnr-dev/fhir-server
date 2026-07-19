class PatientValidator
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
  MEDICAL_RECORD_NUMBER_OID = "urn:oid:1.2.392.100495.20.3.51".freeze
  MEDICAL_RECORD_TYPE_CODE = "MR".freeze

  def self.call(payload)
    new(payload).call
  end

  def initialize(payload)
    @payload = payload
  end

  def call
    errors = []
    warnings = []

    validate_identifier(errors)
    validate_gender(errors)
    validate_birth_date(errors)
    validate_deceased(errors)
    validate_communication(errors)
    validate_medical_record_identifier(warnings)

    Result.new(errors, warnings)
  end

  private

  attr_reader :payload

  def validate_identifier(errors)
    identifiers = payload["identifier"]

    if identifiers.blank?
      errors << {
        code: "required",
        diagnostics: "Patient.identifier is required (JP Core: 1..*)",
        expression: ["Patient.identifier"]
      }
      return
    end

    identifiers.each_with_index do |identifier, index|
      next if identifier.is_a?(Hash) && identifier["value"].present?

      errors << {
        code: "required",
        diagnostics: "Patient.identifier[#{index}].value is required",
        expression: ["Patient.identifier[#{index}].value"]
      }
    end
  end

  def validate_gender(errors)
    gender = payload["gender"]
    return if gender.nil?

    return if VALID_GENDERS.include?(gender)

    errors << {
      code: "value",
      diagnostics: "Invalid Patient.gender '#{gender}'. Must be one of: #{VALID_GENDERS.join(', ')}",
      expression: ["Patient.gender"]
    }
  end

  def validate_birth_date(errors)
    birth_date = payload["birthDate"]
    return if birth_date.nil?

    unless birth_date.is_a?(String) && DATE_FORMATS.any? { |fmt| birth_date.match?(fmt) }
      errors << {
        code: "value",
        diagnostics: "Invalid Patient.birthDate '#{birth_date}'. Expected format YYYY, YYYY-MM, or YYYY-MM-DD",
        expression: ["Patient.birthDate"]
      }
      return
    end

    Date.iso8601(pad_partial_date(birth_date))
  rescue ArgumentError
    errors << {
      code: "value",
      diagnostics: "Invalid Patient.birthDate '#{birth_date}': not a real calendar date",
      expression: ["Patient.birthDate"]
    }
  end

  def pad_partial_date(date)
    case date
    when /\A\d{4}\z/ then "#{date}-01-01"
    when /\A\d{4}-\d{2}\z/ then "#{date}-01"
    else date
    end
  end

  def validate_deceased(errors)
    has_boolean = payload.key?("deceasedBoolean")
    has_datetime = payload.key?("deceasedDateTime")

    if has_boolean && has_datetime
      errors << {
        code: "invariant",
        diagnostics: "Patient.deceased[x] may only have one of deceasedBoolean or deceasedDateTime",
        expression: ["Patient.deceasedBoolean", "Patient.deceasedDateTime"]
      }
    end

    if has_boolean && !(payload["deceasedBoolean"].is_a?(TrueClass) || payload["deceasedBoolean"].is_a?(FalseClass))
      errors << {
        code: "value",
        diagnostics: "Patient.deceasedBoolean must be a boolean",
        expression: ["Patient.deceasedBoolean"]
      }
    end

    return unless has_datetime

    begin
      DateTime.iso8601(payload["deceasedDateTime"])
    rescue ArgumentError, TypeError
      errors << {
        code: "value",
        diagnostics: "Patient.deceasedDateTime must be a valid ISO8601 dateTime",
        expression: ["Patient.deceasedDateTime"]
      }
    end
  end

  def validate_communication(errors)
    communications = payload["communication"]
    return if communications.blank?

    communications.each_with_index do |communication, index|
      language = communication["language"] if communication.is_a?(Hash)

      if language.blank?
        errors << {
          code: "required",
          diagnostics: "Patient.communication[#{index}].language is required when communication is present",
          expression: ["Patient.communication[#{index}].language"]
        }
      end
    end
  end

  def validate_medical_record_identifier(warnings)
    Array(payload["identifier"]).each_with_index do |identifier, index|
      next unless identifier.is_a?(Hash)

      type_code = identifier.dig("type", "coding")&.find { |c| c["code"] == MEDICAL_RECORD_TYPE_CODE }
      next unless type_code

      next if identifier["system"] == MEDICAL_RECORD_NUMBER_OID

      warnings << {
        code: "value",
        diagnostics: "Patient.identifier[#{index}] is typed as medical record number (MR) but system " \
                     "is not the JP Core OID (#{MEDICAL_RECORD_NUMBER_OID})",
        expression: ["Patient.identifier[#{index}].system"]
      }
    end
  end
end
