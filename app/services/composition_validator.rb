class CompositionValidator < ResourceValidator
  private

  def validate
    require_field("status") && validate_binding("status", Fhir::Terminology::COMPOSITION_STATUS)
    require_field("type")
    require_field("title")
    require_field("date") && validate_datetime("date")
    validate_author
    validate_subject
  end

  # Composition.author is 1..*: at least one author reference is required.
  def validate_author
    return unless require_field("author", cardinality: "1..*")

    author = payload["author"]
    return if author.is_a?(Array) && author.any?

    add_error(
      code: "structure",
      diagnostics: "Composition.author must be a non-empty array",
      expression: "Composition.author"
    )
  end

  # Composition.subject is 0..1; when present as a Patient reference it must
  # exist, other target types are left to pass (:skip).
  def validate_subject
    validate_patient_reference("subject", on_non_patient: :skip)
  end
end
