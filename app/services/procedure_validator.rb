class ProcedureValidator < ResourceValidator
  private

  def validate
    require_field("status") && validate_binding("status", Fhir::Terminology::EVENT_STATUS)
    validate_subject
  end

  # Procedure.subject is 1..1 Patient (both base FHIR and JP Core).
  def validate_subject
    return unless require_field("subject", value: payload.dig("subject", "reference"))

    validate_patient_reference("subject", on_non_patient: :reject)
  end
end
