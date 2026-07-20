class CoverageValidator < ResourceValidator
  private

  def validate
    require_field("status") && validate_binding("status", Fhir::Terminology::FINANCIAL_RESOURCE_STATUS)
    validate_beneficiary
    validate_payor
  end

  # Coverage.beneficiary is 1..1 Patient (both base FHIR and JP Core).
  def validate_beneficiary
    return unless require_field("beneficiary", value: payload.dig("beneficiary", "reference"))

    validate_patient_reference("beneficiary", on_non_patient: :reject)
  end

  # Coverage.payor is 1..* Reference(Organization | Patient | RelatedPerson).
  def validate_payor
    require_field("payor", value: Array(payload["payor"]).presence, cardinality: "1..*")
  end
end
