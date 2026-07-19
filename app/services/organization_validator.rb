class OrganizationValidator
  Result = Struct.new(:errors, :warnings) do
    def valid?
      errors.empty?
    end

    def issues
      errors.map { |e| e.merge(severity: "error") } +
        warnings.map { |w| w.merge(severity: "warning") }
    end
  end

  def self.call(payload)
    new(payload).call
  end

  def initialize(payload)
    @payload = payload
  end

  def call
    errors = []
    warnings = []

    validate_org_1_invariant(errors)

    Result.new(errors, warnings)
  end

  private

  attr_reader :payload

  # JP Core / base FHIR invariant org-1:
  # Organization.identifier.count() + Organization.name.count() > 0
  def validate_org_1_invariant(errors)
    return if payload["identifier"].present? || payload["name"].present?

    errors << {
      code: "invariant",
      diagnostics: "Organization must have at least an identifier or a name (org-1)",
      expression: ["Organization"]
    }
  end
end
