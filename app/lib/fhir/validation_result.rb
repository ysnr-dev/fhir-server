module Fhir
  # What validating one payload produced: error and warning issues as
  # { code:, diagnostics:, expression: } hashes. #issues attaches the severity,
  # matching what Fhir::OperationOutcome.build reads.
  ValidationResult = Struct.new(:errors, :warnings) do
    def valid?
      errors.empty?
    end

    def issues
      errors.map { |e| e.merge(severity: "error") } +
        warnings.map { |w| w.merge(severity: "warning") }
    end
  end
end
