class MedicationRequestValidator
  Result = Struct.new(:errors, :warnings) do
    def valid?
      errors.empty?
    end

    def issues
      errors.map { |e| e.merge(severity: "error") } +
        warnings.map { |w| w.merge(severity: "warning") }
    end
  end

  VALID_STATUSES = %w[active on-hold cancelled completed entered-in-error stopped draft unknown].freeze
  VALID_INTENTS = %w[proposal plan order original-order reflex-order filler-order instance-order option].freeze
  RP_NUMBER_SYSTEM = "http://jpfhir.jp/fhir/core/mhlw/IdSystem/Medication-RPGroupNumber".freeze
  ORDER_IN_RP_SYSTEM = "http://jpfhir.jp/fhir/core/mhlw/IdSystem/MedicationAdministrationIndex".freeze
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

    validate_identifier(errors, warnings)
    validate_status(errors)
    validate_intent(errors)
    validate_medication(errors)
    validate_subject(errors)
    validate_authored_on(errors)

    Result.new(errors, warnings)
  end

  private

  attr_reader :payload

  def validate_identifier(errors, warnings)
    identifiers = payload["identifier"]

    if identifiers.blank?
      errors << {
        code: "required",
        diagnostics: "MedicationRequest.identifier is required (JP Core: 2..*)",
        expression: ["MedicationRequest.identifier"]
      }
      return
    end

    identifiers.each_with_index do |identifier, index|
      next if identifier.is_a?(Hash) && identifier["value"].present?

      errors << {
        code: "required",
        diagnostics: "MedicationRequest.identifier[#{index}].value is required",
        expression: ["MedicationRequest.identifier[#{index}].value"]
      }
    end

    systems = identifiers.filter_map { |i| i["system"] if i.is_a?(Hash) }

    unless systems.include?(RP_NUMBER_SYSTEM)
      warnings << {
        code: "value",
        diagnostics: "MedicationRequest.identifier is missing the JP Core rpNumber slice (system: #{RP_NUMBER_SYSTEM})",
        expression: ["MedicationRequest.identifier"]
      }
    end

    unless systems.include?(ORDER_IN_RP_SYSTEM)
      warnings << {
        code: "value",
        diagnostics: "MedicationRequest.identifier is missing the JP Core orderInRp slice (system: #{ORDER_IN_RP_SYSTEM})",
        expression: ["MedicationRequest.identifier"]
      }
    end
  end

  def validate_status(errors)
    status = payload["status"]

    if status.blank?
      errors << {
        code: "required",
        diagnostics: "MedicationRequest.status is required",
        expression: ["MedicationRequest.status"]
      }
      return
    end

    return if VALID_STATUSES.include?(status)

    errors << {
      code: "value",
      diagnostics: "Invalid MedicationRequest.status '#{status}'. Must be one of: #{VALID_STATUSES.join(', ')}",
      expression: ["MedicationRequest.status"]
    }
  end

  def validate_intent(errors)
    intent = payload["intent"]

    if intent.blank?
      errors << {
        code: "required",
        diagnostics: "MedicationRequest.intent is required",
        expression: ["MedicationRequest.intent"]
      }
      return
    end

    return if VALID_INTENTS.include?(intent)

    errors << {
      code: "value",
      diagnostics: "Invalid MedicationRequest.intent '#{intent}'. Must be one of: #{VALID_INTENTS.join(', ')}",
      expression: ["MedicationRequest.intent"]
    }
  end

  def validate_medication(errors)
    if payload["medicationReference"].present?
      errors << {
        code: "invariant",
        diagnostics: "MedicationRequest.medicationReference is not supported by JP Core; use medicationCodeableConcept",
        expression: ["MedicationRequest.medicationReference"]
      }
      return
    end

    return if payload["medicationCodeableConcept"].present?

    errors << {
      code: "required",
      diagnostics: "MedicationRequest.medicationCodeableConcept is required",
      expression: ["MedicationRequest.medicationCodeableConcept"]
    }
  end

  def validate_subject(errors)
    reference = payload.dig("subject", "reference")

    if reference.blank?
      errors << {
        code: "required",
        diagnostics: "MedicationRequest.subject is required",
        expression: ["MedicationRequest.subject"]
      }
      return
    end

    match = reference.match(SUBJECT_REFERENCE_PATTERN)
    unless match
      errors << {
        code: "value",
        diagnostics: "MedicationRequest.subject.reference must reference a Patient (e.g. 'Patient/{id}')",
        expression: ["MedicationRequest.subject.reference"]
      }
      return
    end

    patient = Patient.find_by(id: match[1])
    return if patient && !patient.deleted?

    errors << {
      code: "invalid",
      diagnostics: "MedicationRequest.subject.reference '#{reference}' does not reference an existing Patient",
      expression: ["MedicationRequest.subject.reference"]
    }
  end

  def validate_authored_on(errors)
    authored_on = payload["authoredOn"]

    if authored_on.blank?
      errors << {
        code: "required",
        diagnostics: "MedicationRequest.authoredOn is required",
        expression: ["MedicationRequest.authoredOn"]
      }
      return
    end

    Time.iso8601(authored_on)
  rescue ArgumentError, TypeError
    errors << {
      code: "value",
      diagnostics: "MedicationRequest.authoredOn must be a valid ISO8601 dateTime",
      expression: ["MedicationRequest.authoredOn"]
    }
  end
end
