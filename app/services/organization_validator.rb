class OrganizationValidator < ResourceValidator
  private

  def validate
    validate_org_1_invariant
  end

  # JP Core / base FHIR invariant org-1:
  # Organization.identifier.count() + Organization.name.count() > 0
  def validate_org_1_invariant
    return if payload["identifier"].present? || payload["name"].present?

    add_error(
      code: "invariant",
      diagnostics: "Organization must have at least an identifier or a name (org-1)",
      expression: "Organization"
    )
  end
end
