module Fhir
  # Builds FHIR OperationOutcome resources for error and warning responses.
  module OperationOutcome
    module_function

    # issues: array of { severity:, code:, diagnostics:, expression: (optional) }
    def build(issues)
      {
        "resourceType" => "OperationOutcome",
        "issue" => Array(issues).map { |issue| build_issue(issue) }
      }
    end

    def single(severity:, code:, diagnostics:, expression: nil)
      build([{ severity: severity, code: code, diagnostics: diagnostics, expression: expression }])
    end

    def error(code, diagnostics, expression: nil)
      single(severity: "error", code: code, diagnostics: diagnostics, expression: expression)
    end

    # The outcomes several endpoints answer with, so their wording stays identical.
    def not_found(reference)
      error("not-found", "#{reference} not found")
    end

    def gone(reference)
      error("deleted", "#{reference} has been deleted")
    end

    def unsupported_type(resource_type)
      error("not-supported", "Unsupported resourceType '#{resource_type}'")
    end

    def resource_type_mismatch(expected, payload, code: "structure")
      actual = payload.is_a?(Hash) ? payload["resourceType"] : payload.inspect
      error(code, "resourceType must be '#{expected}', got '#{actual}'")
    end

    def build_issue(issue)
      entry = {
        "severity" => issue[:severity].to_s,
        "code" => issue[:code].to_s,
        "diagnostics" => issue[:diagnostics]
      }
      expression = Array(issue[:expression])
      entry["expression"] = expression unless expression.empty?
      entry
    end
  end
end
