class DocumentReferenceValidator < ResourceValidator
  private

  def validate
    require_field("status") && validate_binding("status", Fhir::Terminology::DOCUMENT_REFERENCE_STATUS)
    validate_binding("docStatus", Fhir::Terminology::COMPOSITION_STATUS)
    validate_content
    validate_datetime("date")
    validate_subject
  end

  # DocumentReference.content is 1..*, each element carrying a mandatory attachment.
  def validate_content
    content = payload["content"]
    return unless require_field("content", cardinality: "1..*")

    unless content.is_a?(Array) && content.any?
      add_error(
        code: "structure",
        diagnostics: "DocumentReference.content must be a non-empty array",
        expression: "DocumentReference.content"
      )
      return
    end

    content.each_with_index do |element, index|
      attachment = element.is_a?(Hash) ? element["attachment"] : nil
      next if attachment.is_a?(Hash) && attachment.present?

      add_error(
        code: "required",
        diagnostics: "DocumentReference.content[#{index}].attachment is required",
        expression: "DocumentReference.content[#{index}].attachment"
      )
    end
  end

  # DocumentReference.subject is 0..1; when present as a Patient reference it
  # must exist, other target types are left to pass (:skip).
  def validate_subject
    validate_patient_reference("subject", on_non_patient: :skip)
  end
end
