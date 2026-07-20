class PatientValidator < ResourceValidator
  private

  def validate
    validate_identifier
    validate_binding("gender", Fhir::Terminology::GENDER)
    validate_date("birthDate")
    validate_deceased
    validate_communication
    validate_medical_record_identifier
  end

  def validate_identifier
    identifiers = payload["identifier"]

    return unless require_field("identifier", cardinality: "1..*")

    identifiers.each_with_index do |identifier, index|
      next if identifier.is_a?(Hash) && identifier["value"].present?

      add_error(
        code: "required",
        diagnostics: "Patient.identifier[#{index}].value is required",
        expression: "Patient.identifier[#{index}].value"
      )
    end
  end

  def validate_deceased
    has_boolean = payload.key?("deceasedBoolean")
    has_datetime = payload.key?("deceasedDateTime")

    if has_boolean && has_datetime
      add_error(
        code: "invariant",
        diagnostics: "Patient.deceased[x] may only have one of deceasedBoolean or deceasedDateTime",
        expression: ["Patient.deceasedBoolean", "Patient.deceasedDateTime"]
      )
    end

    validate_boolean("deceasedBoolean") if has_boolean
    validate_datetime("deceasedDateTime") if has_datetime
  end

  def validate_communication
    communications = payload["communication"]
    return if communications.blank?

    communications.each_with_index do |communication, index|
      language = communication["language"] if communication.is_a?(Hash)
      next if language.present?

      add_error(
        code: "required",
        diagnostics: "Patient.communication[#{index}].language is required when communication is present",
        expression: "Patient.communication[#{index}].language"
      )
    end
  end

  def validate_medical_record_identifier
    Array(payload["identifier"]).each_with_index do |identifier, index|
      next unless identifier.is_a?(Hash)

      type_code = identifier.dig("type", "coding")&.find { |c| c["code"] == Fhir::Terminology::MEDICAL_RECORD_TYPE_CODE }
      next unless type_code
      next if identifier["system"] == Fhir::Terminology::MEDICAL_RECORD_NUMBER_OID

      add_warning(
        code: "value",
        diagnostics: "Patient.identifier[#{index}] is typed as medical record number (MR) but system " \
                     "is not the JP Core OID (#{Fhir::Terminology::MEDICAL_RECORD_NUMBER_OID})",
        expression: "Patient.identifier[#{index}].system"
      )
    end
  end
end
