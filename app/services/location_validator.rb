# JP Core defines no required top-level elements for Location; status and mode
# are optional but carry required value-set bindings when present.
class LocationValidator < ResourceValidator
  private

  def validate
    validate_binding("status", Fhir::Terminology::LOCATION_STATUS)
    validate_binding("mode", Fhir::Terminology::LOCATION_MODE)
  end
end
