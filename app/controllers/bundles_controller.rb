class BundlesController < ApplicationController
  def create
    payload, parse_error = parse_body
    return render_bad_request(parse_error) if parse_error
    return render_bad_request("resourceType must be 'Bundle'") unless payload["resourceType"] == "Bundle"

    result = BundleProcessor.call(payload, base_url: base_url)
    render json: result.body, status: result.status, content_type: FhirResponse::FHIR_CONTENT_TYPE
  end

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

  def render_bad_request(message)
    render_operation_outcome_single(
      status: :bad_request,
      severity: "error",
      code: "structure",
      diagnostics: message
    )
  end
end
