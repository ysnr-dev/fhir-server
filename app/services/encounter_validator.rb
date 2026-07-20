class EncounterValidator < ResourceValidator
  private

  def validate
    require_field("status") && validate_binding("status", Fhir::Terminology::ENCOUNTER_STATUS)
    validate_class
  end

  # class is 1..1. Its binding to v3 ActEncounterCode is extensible, so the code
  # value is not constrained here -- only that a class coding with a code is present.
  def validate_class
    require_field("class", value: payload.dig("class", "code"))
  end
end
