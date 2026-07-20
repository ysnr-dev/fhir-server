class MedicationRequestValidator < ResourceValidator
  private

  def validate
    validate_identifier
    require_field("status") && validate_binding("status", Fhir::Terminology::MEDICATION_REQUEST_STATUS)
    require_field("intent") && validate_binding("intent", Fhir::Terminology::MEDICATION_REQUEST_INTENT)
    validate_medication
    validate_subject
    validate_authored_on
  end

  def validate_identifier
    identifiers = payload["identifier"]

    return unless require_field("identifier", cardinality: "2..*")

    identifiers.each_with_index do |identifier, index|
      next if identifier.is_a?(Hash) && identifier["value"].present?

      add_error(
        code: "required",
        diagnostics: "MedicationRequest.identifier[#{index}].value is required",
        expression: "MedicationRequest.identifier[#{index}].value"
      )
    end

    systems = identifiers.filter_map { |i| i["system"] if i.is_a?(Hash) }

    warn_missing_slice(systems, Fhir::Terminology::MEDICATION_RP_NUMBER_SYSTEM, "rpNumber")
    warn_missing_slice(systems, Fhir::Terminology::MEDICATION_ORDER_IN_RP_SYSTEM, "orderInRp")
  end

  def warn_missing_slice(systems, system, slice_name)
    return if systems.include?(system)

    add_warning(
      code: "value",
      diagnostics: "MedicationRequest.identifier is missing the JP Core #{slice_name} slice (system: #{system})",
      expression: "MedicationRequest.identifier"
    )
  end

  def validate_medication
    if payload["medicationReference"].present?
      add_error(
        code: "invariant",
        diagnostics: "MedicationRequest.medicationReference is not supported by JP Core; use medicationCodeableConcept",
        expression: "MedicationRequest.medicationReference"
      )
      return
    end

    require_field("medicationCodeableConcept")
  end

  def validate_subject
    return unless require_field("subject", value: payload.dig("subject", "reference"))

    validate_patient_reference("subject", on_non_patient: :reject)
  end

  def validate_authored_on
    return unless require_field("authoredOn")

    validate_datetime("authoredOn")
  end
end
