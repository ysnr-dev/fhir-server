class RelatedPersonValidator < ResourceValidator
  private

  def validate
    validate_patient
    validate_binding("gender", Fhir::Terminology::GENDER)
    validate_date("birthDate")
    validate_boolean("active")
  end

  # RelatedPerson.patient is the one mandatory element in both base FHIR R4 and
  # JP_RelatedPerson: a related person only exists relative to a patient.
  def validate_patient
    return unless require_field("patient", value: payload.dig("patient", "reference"),
                                           expression: "RelatedPerson.patient.reference",
                                           cardinality: "1..1")

    validate_patient_reference("patient", on_non_patient: :reject)
  end
end
