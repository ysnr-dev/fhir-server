class SpecimenValidator < ResourceValidator
  private

  def validate
    validate_binding("status", Fhir::Terminology::SPECIMEN_STATUS)
    validate_subject
  end

  # Specimen.subject is 0..1; JP Core constrains it to Patient. When present as a
  # Patient reference it must exist, but other target types are left to pass (:skip).
  def validate_subject
    validate_patient_reference("subject", on_non_patient: :skip)
  end
end
