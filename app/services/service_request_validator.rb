class ServiceRequestValidator
  Result = Struct.new(:errors, :warnings) do
    def valid?
      errors.empty?
    end

    def issues
      errors.map { |e| e.merge(severity: "error") } +
        warnings.map { |w| w.merge(severity: "warning") }
    end
  end

  VALID_STATUSES = %w[draft active on-hold revoked completed entered-in-error unknown].freeze
  VALID_INTENTS = %w[proposal plan directive order original-order reflex-order filler-order instance-order option].freeze
  SUBJECT_REFERENCE_PATTERN = %r{\APatient/(.+)\z}.freeze

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
    validate_intent(errors)
    validate_subject(errors)

    Result.new(errors, warnings)
  end

  private

  attr_reader :payload

  def validate_status(errors)
    status = payload["status"]

    if status.blank?
      errors << {
        code: "required",
        diagnostics: "ServiceRequest.status is required",
        expression: ["ServiceRequest.status"]
      }
      return
    end

    return if VALID_STATUSES.include?(status)

    errors << {
      code: "value",
      diagnostics: "Invalid ServiceRequest.status '#{status}'. Must be one of: #{VALID_STATUSES.join(', ')}",
      expression: ["ServiceRequest.status"]
    }
  end

  def validate_intent(errors)
    intent = payload["intent"]

    if intent.blank?
      errors << {
        code: "required",
        diagnostics: "ServiceRequest.intent is required",
        expression: ["ServiceRequest.intent"]
      }
      return
    end

    return if VALID_INTENTS.include?(intent)

    errors << {
      code: "value",
      diagnostics: "Invalid ServiceRequest.intent '#{intent}'. Must be one of: #{VALID_INTENTS.join(', ')}",
      expression: ["ServiceRequest.intent"]
    }
  end

  # subject is required (1..1). Only Patient/{id} references are existence-checked;
  # other reference types (e.g. Location) are accepted without a lookup.
  def validate_subject(errors)
    reference = payload.dig("subject", "reference")

    if reference.blank?
      errors << {
        code: "required",
        diagnostics: "ServiceRequest.subject is required",
        expression: ["ServiceRequest.subject"]
      }
      return
    end

    match = reference.match(SUBJECT_REFERENCE_PATTERN)
    return unless match

    patient = Patient.find_by(id: match[1])
    return if patient && !patient.deleted?

    errors << {
      code: "invalid",
      diagnostics: "ServiceRequest.subject.reference '#{reference}' does not reference an existing Patient",
      expression: ["ServiceRequest.subject.reference"]
    }
  end
end
