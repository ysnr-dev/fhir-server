# Group is the one registered type JP Core does not profile, so it is validated
# against base FHIR R4 alone -- Fhir::Profile::Validator skips it (the registry
# points at the bare HL7 StructureDefinition, which is not vendored), making this
# validator the only check that runs.
class GroupValidator < ResourceValidator
  PROFILE_LABEL = "FHIR R4".freeze

  private

  def validate
    require_field("type", cardinality: "1..1") &&
      validate_binding("type", Fhir::Terminology::GROUP_TYPE)
    require_field("actual", cardinality: "1..1") &&
      validate_boolean("actual")
    validate_members
  end

  # grp-1: "Can only have members if group is 'actual'" -- a descriptive group
  # (actual == false) defines a cohort by characteristics, not by roster.
  def validate_members
    members = payload["member"]
    return if members.blank?

    if payload["actual"] == false
      add_error(code: "invariant",
                diagnostics: "Group.member is only allowed when Group.actual is true (grp-1)",
                expression: "Group.member")
    end

    unless members.is_a?(Array)
      add_error(code: "structure", diagnostics: "Group.member must be an array", expression: "Group.member")
      return
    end

    members.each_with_index { |member, index| validate_member(member, index) }
  end

  # Patient members are existence-checked because Group/$export resolves exactly
  # those references into the exported patient set: a dangling one would silently
  # shrink the export rather than fail it. Other target types (Practitioner,
  # Device, nested Group) are structural-only, as everywhere else in this server.
  def validate_member(member, index)
    reference = member.is_a?(Hash) ? member.dig("entity", "reference") : nil
    if reference.blank?
      add_error(code: "required",
                diagnostics: "Group.member.entity.reference is required (#{PROFILE_LABEL}: 1..1)",
                expression: "Group.member[#{index}].entity.reference")
      return
    end

    patient_id = reference[%r{\APatient/(.+)\z}, 1]
    return if patient_id.nil?

    patient = Patient.find_by(id: patient_id)
    return if patient && !patient.deleted?

    add_error(code: "invalid",
              diagnostics: "Group.member.entity.reference '#{reference}' does not reference an existing Patient",
              expression: "Group.member[#{index}].entity.reference")
  end
end
