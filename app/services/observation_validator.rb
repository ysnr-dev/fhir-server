class ObservationValidator < ResourceValidator
  private

  def validate
    require_field("status") && validate_binding("status", Fhir::Terminology::OBSERVATION_STATUS)
    # code is 1..1 (what was observed, e.g. a LOINC concept).
    require_field("code")
    validate_subject
  end

  # JP_Observation_Common constrains subject to 1..1 Patient.
  def validate_subject
    return unless require_field("subject", value: payload.dig("subject", "reference"))

    validate_patient_reference("subject", on_non_patient: :reject)
  end
end
