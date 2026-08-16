# Slot is not profiled by JP Core, so it is validated against base FHIR R4 alone
# -- see ScheduleValidator for the arrangement.
class SlotValidator < ResourceValidator
  PROFILE_LABEL = "FHIR R4".freeze

  private

  def validate
    require_field("status", cardinality: "1..1") &&
      validate_binding("status", Fhir::Terminology::SLOT_STATUS)
    require_field("schedule", value: payload.dig("schedule", "reference"),
                              expression: "Slot.schedule.reference", cardinality: "1..1")
    validate_schedule_reference
    require_field("start", cardinality: "1..1")
    require_field("end", cardinality: "1..1")
    validate_instant("start")
    validate_instant("end")
    validate_order
    validate_boolean("overbooked")
  end

  # Structural only, like every non-Patient reference on this server: a Slot is
  # routinely written in the same transaction Bundle as its Schedule, so an
  # existence check here would reject the ordinary bulk load.
  def validate_schedule_reference
    reference = payload.dig("schedule", "reference")
    return if reference.blank? || reference.match?(%r{\ASchedule/.+\z})

    add_error(code: "value",
              diagnostics: "Slot.schedule.reference must reference a Schedule (e.g. 'Schedule/{id}')",
              expression: "Slot.schedule.reference")
  end

  # R4 states no invariant for this, but a slot whose end precedes its start has
  # no duration to book: `start` search would still find it and the booking screen
  # would offer an opening that cannot be filled.
  def validate_order
    starts_at = Fhir::FieldExtractor.datetime(payload["start"])
    ends_at = Fhir::FieldExtractor.datetime(payload["end"])
    return if starts_at.nil? || ends_at.nil? || ends_at > starts_at

    add_error(code: "invariant",
              diagnostics: "Slot.end must be after Slot.start",
              expression: "Slot.end")
  end
end
