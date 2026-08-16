# Schedule is not profiled by JP Core, so it is validated against base FHIR R4
# alone -- Fhir::Profile::Validator skips it (the registry points at the bare HL7
# StructureDefinition, which is not vendored), making this validator the only
# check that runs. Same arrangement as TaskValidator / GroupValidator.
class ScheduleValidator < ResourceValidator
  PROFILE_LABEL = "FHIR R4".freeze

  private

  def validate
    validate_boolean("active")
    validate_actors
    validate_planning_horizon
  end

  # Schedule.actor is 1..* -- a schedule that names no practitioner, room, or
  # device is not a schedule of anything, and `actor` search matches it by jsonb
  # containment, so a non-array here would be silently unsearchable.
  def validate_actors
    return unless require_field("actor", cardinality: "1..*")

    actors = payload["actor"]
    unless actors.is_a?(Array)
      add_error(code: "structure",
                diagnostics: "Schedule.actor must be an array of References (searched by `actor`)",
                expression: "Schedule.actor")
      return
    end

    actors.each_with_index do |actor, index|
      reference = actor.is_a?(Hash) ? actor["reference"] : nil
      next if reference.present?

      add_error(code: "required",
                diagnostics: "Schedule.actor.reference is required (#{PROFILE_LABEL}: 1..1)",
                expression: "Schedule.actor[#{index}].reference")
    end
  end

  # planningHorizon bounds the period the slots hang off, and `date` searches it
  # as a period: an inverted one would match nothing while looking correct.
  def validate_planning_horizon
    start_value = payload.dig("planningHorizon", "start")
    end_value = payload.dig("planningHorizon", "end")
    validate_datetime("planningHorizon.start", value: start_value,
                                               expression: "Schedule.planningHorizon.start")
    validate_datetime("planningHorizon.end", value: end_value,
                                             expression: "Schedule.planningHorizon.end")

    starts_at = Fhir::FieldExtractor.datetime(start_value)
    ends_at = Fhir::FieldExtractor.datetime(end_value)
    return if starts_at.nil? || ends_at.nil? || ends_at >= starts_at

    add_error(code: "invariant",
              diagnostics: "Schedule.planningHorizon.end must be at or after planningHorizon.start",
              expression: "Schedule.planningHorizon")
  end
end
