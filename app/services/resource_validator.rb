# Base class for the per-resource FHIR validators. Subclasses implement #validate,
# calling the shared check helpers (or appending bespoke issues via #add_error /
# #add_warning). The invocation contract expected by Fhir::Operation is preserved:
# `SomeValidator.call(payload)` returns an object responding to #valid? and #issues.
#
# Issues are accumulated as { code:, diagnostics:, expression: } hashes; severity is
# attached by Result#issues, matching what Fhir::OperationOutcome.build reads.
class ResourceValidator
  Result = Struct.new(:errors, :warnings) do
    def valid?
      errors.empty?
    end

    def issues
      errors.map { |e| e.merge(severity: "error") } +
        warnings.map { |w| w.merge(severity: "warning") }
    end
  end

  # Accepted partial-date formats for FHIR `date` elements (YYYY, YYYY-MM, YYYY-MM-DD).
  DATE_FORMATS = [
    /\A\d{4}\z/,
    /\A\d{4}-\d{2}\z/,
    /\A\d{4}-\d{2}-\d{2}\z/
  ].freeze

  def self.call(payload)
    new(payload).call
  end

  def initialize(payload)
    @payload = payload
    @errors = []
    @warnings = []
  end

  def call
    validate
    Result.new(@errors, @warnings)
  end

  private

  attr_reader :payload

  # The FHIR resourceType this validator covers, derived from the class name
  # (PatientValidator -> "Patient"), used to build expression paths.
  def resource_type
    @resource_type ||= self.class.name.sub(/Validator\z/, "")
  end

  def add_error(code:, diagnostics:, expression:)
    @errors << { code: code, diagnostics: diagnostics, expression: Array(expression) }
  end

  def add_warning(code:, diagnostics:, expression:)
    @warnings << { code: code, diagnostics: diagnostics, expression: Array(expression) }
  end

  # --- reusable checks ----------------------------------------------------

  # Requires a top-level field to be present. `false` counts as present (for
  # boolean elements). Returns true when present so callers can guard further
  # checks. `cardinality:` appends a JP Core note, e.g. "(JP Core: 1..*)".
  def require_field(field, value: payload[field], expression: "#{resource_type}.#{field}", cardinality: nil)
    return true if value == false || value.present?

    note = cardinality ? " (JP Core: #{cardinality})" : ""
    add_error(code: "required", diagnostics: "#{resource_type}.#{field} is required#{note}", expression: expression)
    false
  end

  # Checks an optional coded value against a required ValueSet binding. No-op when
  # the value is absent (optional element); an unbound value is a "value" error.
  def validate_binding(field, valueset, value: payload[field], expression: "#{resource_type}.#{field}")
    return if value.blank?
    return if valueset.include?(value)

    add_error(
      code: "value",
      diagnostics: "Invalid #{resource_type}.#{field} '#{value}'. Must be one of: #{valueset.join(', ')}",
      expression: expression
    )
  end

  # Validates a FHIR `date` element: partial-date format then real-calendar check.
  # No-op when absent (caller enforces requiredness separately if needed).
  def validate_date(field, value: payload[field], expression: "#{resource_type}.#{field}")
    return if value.nil?

    unless value.is_a?(String) && DATE_FORMATS.any? { |fmt| value.match?(fmt) }
      add_error(
        code: "value",
        diagnostics: "Invalid #{resource_type}.#{field} '#{value}'. Expected format YYYY, YYYY-MM, or YYYY-MM-DD",
        expression: expression
      )
      return
    end

    Date.iso8601(pad_partial_date(value))
  rescue ArgumentError
    add_error(
      code: "value",
      diagnostics: "Invalid #{resource_type}.#{field} '#{value}': not a real calendar date",
      expression: expression
    )
  end

  # Validates a FHIR `dateTime` element. No-op when absent.
  def validate_datetime(field, value: payload[field], expression: "#{resource_type}.#{field}")
    return if value.nil?

    Time.iso8601(value)
  rescue ArgumentError, TypeError
    add_error(
      code: "value",
      diagnostics: "#{resource_type}.#{field} must be a valid ISO8601 dateTime",
      expression: expression
    )
  end

  # Validates that an optional element is a JSON boolean. No-op when absent.
  def validate_boolean(field, value: payload[field], expression: "#{resource_type}.#{field}")
    return unless payload.key?(field)
    return if value == true || value == false

    add_error(code: "value", diagnostics: "#{resource_type}.#{field} must be a boolean", expression: expression)
  end

  # Validates a subject-style Patient reference. `on_non_patient:` controls what
  # happens for a reference that is not `Patient/{id}`:
  #   :reject -> "value" error (the element must reference a Patient)
  #   :skip   -> accepted without a lookup (other target types are allowed)
  # A `Patient/{id}` reference is always existence-checked (must exist, not deleted).
  def validate_patient_reference(field, on_non_patient:)
    reference = payload.dig(field, "reference")
    return if reference.blank?

    match = reference.match(%r{\APatient/(.+)\z})
    unless match
      if on_non_patient == :reject
        add_error(
          code: "value",
          diagnostics: "#{resource_type}.#{field}.reference must reference a Patient (e.g. 'Patient/{id}')",
          expression: "#{resource_type}.#{field}.reference"
        )
      end
      return
    end

    patient = Patient.find_by(id: match[1])
    return if patient && !patient.deleted?

    add_error(
      code: "invalid",
      diagnostics: "#{resource_type}.#{field}.reference '#{reference}' does not reference an existing Patient",
      expression: "#{resource_type}.#{field}.reference"
    )
  end

  def pad_partial_date(date)
    case date
    when /\A\d{4}\z/ then "#{date}-01-01"
    when /\A\d{4}-\d{2}\z/ then "#{date}-01"
    else date
    end
  end
end
