# Task is not profiled by JP Core, so it is validated against base FHIR R4 alone --
# Fhir::Profile::Validator skips it (the registry points at the bare HL7
# StructureDefinition, which is not vendored), making this validator the only
# check that runs. Same arrangement as GroupValidator.
class TaskValidator < ResourceValidator
  PROFILE_LABEL = "FHIR R4".freeze

  # 0..* Reference elements whose containment is what `based-on` / `part-of`
  # search on: a non-array here is silently unsearchable rather than obviously
  # broken, so the shape is checked up front.
  REFERENCE_ARRAYS = { "basedOn" => "based-on", "partOf" => "part-of" }.freeze

  private

  def validate
    require_field("status", cardinality: "1..1") &&
      validate_binding("status", Fhir::Terminology::TASK_STATUS)
    require_field("intent", cardinality: "1..1") &&
      validate_binding("intent", Fhir::Terminology::TASK_INTENT)
    validate_binding("priority", Fhir::Terminology::REQUEST_PRIORITY)
    validate_datetime("authoredOn")
    validate_datetime("lastModified")
    validate_last_modified_order
    validate_for
    REFERENCE_ARRAYS.each { |field, param| validate_reference_array(field, param) }
  end

  # inv-1: "Last modified date must be greater than or equal to authored-on date."
  # Only checked when both parse -- a malformed value is already reported by
  # validate_datetime, and reporting it twice would be noise.
  def validate_last_modified_order
    authored_on = Fhir::FieldExtractor.datetime(payload["authoredOn"])
    last_modified = Fhir::FieldExtractor.datetime(payload["lastModified"])
    return if authored_on.nil? || last_modified.nil?
    return if last_modified >= authored_on

    add_error(
      code: "invariant",
      diagnostics: "Task.lastModified must be at or after Task.authoredOn (inv-1)",
      expression: "Task.lastModified"
    )
  end

  # Task.for is 0..1 in FHIR, but it is the only element that puts a Task in a
  # patient compartment: without it the Task is invisible to a patient-context
  # token, to Patient/$everything, and to Patient/$export. That is a real
  # decision rather than an error, so it warns rather than rejecting.
  # Only Patient/{id} references are existence-checked; other target types
  # (Task.for is Reference(Any)) are accepted without a lookup.
  def validate_for
    if payload.dig("for", "reference").blank?
      add_warning(
        code: "informational",
        diagnostics: "Task.for is absent, so this Task belongs to no patient compartment " \
                     "(excluded from Patient/$everything, Patient/$export, and patient-context reads)",
        expression: "Task.for"
      )
      return
    end

    validate_patient_reference("for", on_non_patient: :skip)
  end

  def validate_reference_array(field, param)
    value = payload[field]
    return if value.nil? || value.is_a?(Array)

    add_error(
      code: "structure",
      diagnostics: "Task.#{field} must be an array of References (searched by `#{param}`)",
      expression: "Task.#{field}"
    )
  end
end
