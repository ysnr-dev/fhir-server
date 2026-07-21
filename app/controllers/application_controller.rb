class ApplicationController < ActionController::API
  include FhirResponse

  rescue_from StandardError, with: :render_internal_error

  private

  def parse_body
    body = request.body.read
    return [nil, "Request body must not be empty"] if body.blank?

    parsed = JSON.parse(body)
    return [nil, "Request body must be a JSON object"] unless parsed.is_a?(Hash)

    [parsed, nil]
  rescue JSON::ParserError => e
    [nil, "Malformed JSON: #{e.message}"]
  end

  # Like parse_body, but for JSON Patch documents, which are arrays.
  def parse_patch_body
    body = request.body.read
    return [nil, "Request body must not be empty"] if body.blank?

    parsed = JSON.parse(body)
    return [nil, "Request body must be a JSON array of patch operations"] unless parsed.is_a?(Array)

    [parsed, nil]
  rescue JSON::ParserError => e
    [nil, "Malformed JSON: #{e.message}"]
  end

  # Returns Fhir::HistoryParams, or nil after rendering 400 for a bad _since.
  def parse_history_params
    Fhir::HistoryParams.parse(request.query_string)
  rescue Fhir::HistoryParams::InvalidSince => e
    render_operation_outcome_single(
      status: :bad_request,
      severity: "error",
      code: "value",
      diagnostics: e.message
    )
    nil
  end

  def render_bad_request(message)
    render_operation_outcome_single(
      status: :bad_request,
      severity: "error",
      code: "structure",
      diagnostics: message
    )
  end

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
