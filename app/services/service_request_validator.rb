class ServiceRequestValidator < ResourceValidator
  private

  def validate
    require_field("status") && validate_binding("status", Fhir::Terminology::SERVICE_REQUEST_STATUS)
    require_field("intent") && validate_binding("intent", Fhir::Terminology::SERVICE_REQUEST_INTENT)
    validate_subject
  end

  # subject is required (1..1). Only Patient/{id} references are existence-checked;
  # other reference types (e.g. Location) are accepted without a lookup.
  def validate_subject
    return unless require_field("subject", value: payload.dig("subject", "reference"))

    validate_patient_reference("subject", on_non_patient: :skip)
  end
end
