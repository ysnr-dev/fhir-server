# JP Core has no truly required top-level elements for Practitioner
# (qualification.code is 1..1 only when qualification is present at all).
class PractitionerValidator < ResourceValidator
  private

  def validate
    validate_binding("gender", Fhir::Terminology::GENDER)
    validate_date("birthDate")
  end
end
