class ImagingStudyValidator < ResourceValidator
  private

  def validate
    require_field("status") && validate_binding("status", Fhir::Terminology::IMAGING_STUDY_STATUS)
    validate_subject
  end

  # ImagingStudy.subject is 1..1; JP Core constrains it to Patient.
  def validate_subject
    return unless require_field("subject", value: payload.dig("subject", "reference"))

    validate_patient_reference("subject", on_non_patient: :reject)
  end
end
