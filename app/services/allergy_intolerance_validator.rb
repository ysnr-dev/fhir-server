class AllergyIntoleranceValidator < ResourceValidator
  private

  def validate
    validate_concept_binding("clinicalStatus", Fhir::Terminology::ALLERGY_CLINICAL_STATUS)
    validate_concept_binding("verificationStatus", Fhir::Terminology::ALLERGY_VERIFICATION_STATUS)
    validate_binding("type", Fhir::Terminology::ALLERGY_TYPE)
    validate_categories
    validate_binding("criticality", Fhir::Terminology::ALLERGY_CRITICALITY)
    validate_patient
  end

  # category is 0..* code.
  def validate_categories
    Array(payload["category"]).each do |category|
      validate_binding("category", Fhir::Terminology::ALLERGY_CATEGORY, value: category)
    end
  end

  # AllergyIntolerance.patient is 1..1 Patient (both base FHIR and JP Core).
  def validate_patient
    return unless require_field("patient", value: payload.dig("patient", "reference"))

    validate_patient_reference("patient", on_non_patient: :reject)
  end
end
