class MedicationValidator < ResourceValidator
  private

  def validate
    validate_binding("status", Fhir::Terminology::MEDICATION_STATUS)
    # JP_Medication constrains Medication.code to 1..1 (YJ / HOT code).
    require_field("code")
  end
end
