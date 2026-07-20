class MedicationStatementValidator < ResourceValidator
  private

  def validate
    require_field("status") && validate_binding("status", Fhir::Terminology::MEDICATION_STATEMENT_STATUS)
    validate_medication
    validate_subject
  end

  # medication[x] is 1..1: either the CodeableConcept or Reference form must be
  # present. JP Core allows medicationReference (e.g. a contained Medication).
  def validate_medication
    return if payload["medicationCodeableConcept"].present? || payload["medicationReference"].present?

    add_error(
      code: "required",
      diagnostics: "#{resource_type}.medication[x] (medicationCodeableConcept or medicationReference) is required",
      expression: %w[MedicationStatement.medicationCodeableConcept MedicationStatement.medicationReference]
    )
  end

  def validate_subject
    return unless require_field("subject", value: payload.dig("subject", "reference"))

    validate_patient_reference("subject", on_non_patient: :reject)
  end
end
