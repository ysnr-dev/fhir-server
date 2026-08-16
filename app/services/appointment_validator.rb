# Appointment is not profiled by JP Core, so it is validated against base FHIR R4
# alone -- see ScheduleValidator for the arrangement. The R4 invariants app-1
# through app-4 are implemented here; they are FHIRPath constraints, which the
# profile engine does not evaluate even for the resources it does cover.
class AppointmentValidator < ResourceValidator
  PROFILE_LABEL = "FHIR R4".freeze

  # app-3: only these statuses may omit start/end -- everything else is a booking
  # on the calendar and therefore has a time.
  UNSCHEDULED_STATUSES = %w[proposed cancelled waitlist].freeze
  # app-4: cancelationReason is meaningful only once the appointment fell through.
  CANCELED_STATUSES = %w[cancelled noshow].freeze

  private

  def validate
    require_field("status", cardinality: "1..1") &&
      validate_binding("status", Fhir::Terminology::APPOINTMENT_STATUS)
    validate_instant("start")
    validate_instant("end")
    validate_order
    validate_start_end_presence
    validate_cancelation_reason
    validate_participants
    validate_patient_participant
  end

  def validate_order
    starts_at = Fhir::FieldExtractor.datetime(payload["start"])
    ends_at = Fhir::FieldExtractor.datetime(payload["end"])
    return if starts_at.nil? || ends_at.nil? || ends_at > starts_at

    add_error(code: "invariant",
              diagnostics: "Appointment.end must be after Appointment.start",
              expression: "Appointment.end")
  end

  # app-2: "Either start and end are specified, or neither."
  # app-3: "Only proposed or cancelled appointments can be missing start/end dates."
  def validate_start_end_presence
    has_start = payload["start"].present?
    has_end = payload["end"].present?

    if has_start != has_end
      add_error(code: "invariant",
                diagnostics: "Appointment.start and Appointment.end must both be present or both absent (app-2)",
                expression: %w[Appointment.start Appointment.end])
      return
    end
    return if has_start || UNSCHEDULED_STATUSES.include?(payload["status"])

    add_error(
      code: "invariant",
      diagnostics: "Appointment.start / Appointment.end may only be omitted when status is one of: " \
                   "#{UNSCHEDULED_STATUSES.join(', ')} (app-3)",
      expression: "Appointment.start"
    )
  end

  # app-4: "Cancelation reason is only used for appointments that have been
  # cancelled, or no-show."
  def validate_cancelation_reason
    return if payload["cancelationReason"].blank?
    return if CANCELED_STATUSES.include?(payload["status"])

    add_error(
      code: "invariant",
      diagnostics: "Appointment.cancelationReason is only allowed when status is one of: " \
                   "#{CANCELED_STATUSES.join(', ')} (app-4)",
      expression: "Appointment.cancelationReason"
    )
  end

  # participant is 1..*, and `actor` / `patient` / `location` search all read it by
  # jsonb containment, so a non-array is silently unsearchable rather than
  # obviously broken.
  def validate_participants
    return unless require_field("participant", cardinality: "1..*")

    participants = payload["participant"]
    unless participants.is_a?(Array)
      add_error(code: "structure",
                diagnostics: "Appointment.participant must be an array (searched by `actor` / `patient`)",
                expression: "Appointment.participant")
      return
    end

    participants.each_with_index { |participant, index| validate_participant(participant, index) }
  end

  def validate_participant(participant, index)
    unless participant.is_a?(Hash)
      add_error(code: "structure",
                diagnostics: "Appointment.participant entries must be objects",
                expression: "Appointment.participant[#{index}]")
      return
    end

    # app-1: "Either the type or actor on the participant SHALL be specified."
    if participant["type"].blank? && participant.dig("actor", "reference").blank?
      add_error(code: "invariant",
                diagnostics: "Appointment.participant requires either type or actor (app-1)",
                expression: "Appointment.participant[#{index}]")
    end

    validate_participant_status(participant["status"], index)
    validate_binding("participant.required", Fhir::Terminology::PARTICIPANT_REQUIRED,
                     value: participant["required"],
                     expression: "Appointment.participant[#{index}].required")
  end

  def validate_participant_status(status, index)
    expression = "Appointment.participant[#{index}].status"
    if status.blank?
      add_error(code: "required",
                diagnostics: "Appointment.participant.status is required (#{PROFILE_LABEL}: 1..1)",
                expression: expression)
      return
    end

    validate_binding("participant.status", Fhir::Terminology::PARTICIPATION_STATUS,
                     value: status, expression: expression)
  end

  # The Patient participant is what puts an Appointment in a patient compartment
  # (see Fhir::ExtractionDefinitions::Appointment). Without one the appointment is
  # invisible to a patient-context token, to Patient/$everything, and to
  # Patient/$export -- true of a blocked-out slot or a staff meeting, so it warns
  # rather than rejecting. When present it is existence-checked, as everywhere
  # else a Patient is referenced on this server.
  def validate_patient_participant
    reference = Fhir::FieldExtractor.actor_patient_reference(payload["participant"])
    if reference.blank?
      add_warning(
        code: "informational",
        diagnostics: "Appointment has no Patient participant, so it belongs to no patient compartment " \
                     "(excluded from Patient/$everything, Patient/$export, and patient-context reads)",
        expression: "Appointment.participant"
      )
      return
    end

    patient = Patient.find_by(id: reference.delete_prefix("Patient/"))
    return if patient && !patient.deleted?

    add_error(
      code: "invalid",
      diagnostics: "Appointment.participant.actor.reference '#{reference}' does not reference an existing Patient",
      expression: "Appointment.participant"
    )
  end
end
