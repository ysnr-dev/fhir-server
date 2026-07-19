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
