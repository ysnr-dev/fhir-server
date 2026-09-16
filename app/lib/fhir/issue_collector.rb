module Fhir
  # Accumulates validation issues for a validator class and hands them back as
  # a Fhir::ValidationResult. Shared by the hand-written per-resource validators
  # (ResourceValidator) and the profile engine (Fhir::Profile::Validator).
  module IssueCollector
    private

    def errors
      @errors ||= []
    end

    def warnings
      @warnings ||= []
    end

    def add_error(code:, diagnostics:, expression:)
      errors << { code: code, diagnostics: diagnostics, expression: Array(expression) }
    end

    def add_warning(code:, diagnostics:, expression:)
      warnings << { code: code, diagnostics: diagnostics, expression: Array(expression) }
    end

    def validation_result
      ValidationResult.new(errors, warnings)
    end
  end
end
