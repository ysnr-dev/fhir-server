class ImmunizationValidator < ResourceValidator
  private

  def validate
    require_field("status") && validate_binding("status", Fhir::Terminology::IMMUNIZATION_STATUS)
    require_field("vaccineCode")
    validate_patient
    require_field("occurrenceDateTime")
    validate_datetime("occurrenceDateTime")
  end

  # Immunization.patient is 1..1 Patient (both base FHIR and JP Core).
  def validate_patient
    return unless require_field("patient", value: payload.dig("patient", "reference"))

    validate_patient_reference("patient", on_non_patient: :reject)
  end
end
