# JP Core defines no required top-level elements for PractitionerRole; validation
# is limited to type-checking the optional `active` flag.
class PractitionerRoleValidator < ResourceValidator
  private

  def validate
    validate_boolean("active")
  end
end
