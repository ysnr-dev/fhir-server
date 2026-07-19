class ApplicationController < ActionController::API
  include FhirResponse

  rescue_from StandardError, with: :render_internal_error

  private

  def render_internal_error(exception)
    Rails.logger.error("#{exception.class}: #{exception.message}\n#{exception.backtrace&.first(10)&.join("\n")}")
    render_operation_outcome_single(
      status: :internal_server_error,
      severity: "error",
      code: "exception",
      diagnostics: Rails.env.production? ? "An internal error occurred" : exception.message
    )
  end
end
