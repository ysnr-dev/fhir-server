class DiagnosticReportValidator < ResourceValidator
  private

  def validate
    require_field("status") && validate_binding("status", Fhir::Terminology::DIAGNOSTIC_REPORT_STATUS)
    # code is 1..1 (the name/code of the report, e.g. a LOINC concept).
    require_field("code")
    validate_subject
  end

  # DiagnosticReport.subject is 0..1 in base FHIR but 1..1 Patient in JP Core.
  def validate_subject
    return unless require_field("subject", value: payload.dig("subject", "reference"))

    validate_patient_reference("subject", on_non_patient: :reject)
  end
end
