class ConditionValidator < ResourceValidator
  private

  def validate
    validate_concept_binding("clinicalStatus", Fhir::Terminology::CONDITION_CLINICAL_STATUS)
    validate_concept_binding("verificationStatus", Fhir::Terminology::CONDITION_VERIFICATION_STATUS)
    validate_subject
  end

  # Condition.subject is 1..1 Patient (both base FHIR and JP Core).
  def validate_subject
    return unless require_field("subject", value: payload.dig("subject", "reference"))

    validate_patient_reference("subject", on_non_patient: :reject)
  end
end
