module FhirResponse
  extend ActiveSupport::Concern

  FHIR_CONTENT_TYPE = "application/fhir+json".freeze

  def render_fhir_resource(resource, status: :ok, location: nil, version_id: nil)
    response.set_header("Location", location) if location
    response.set_header("ETag", %(W/"#{version_id}")) if version_id
    render json: resource, status: status, content_type: FHIR_CONTENT_TYPE
  end

  def render_operation_outcome(status:, issues:)
    render json: Fhir::OperationOutcome.build(issues), status: status, content_type: FHIR_CONTENT_TYPE
  end

  def render_operation_outcome_single(status:, severity:, code:, diagnostics:, expression: nil)
    render_operation_outcome(
      status: status,
      issues: [{ severity: severity, code: code, diagnostics: diagnostics, expression: expression }]
    )
  end

  # Renders a Fhir::Operation::Result (see app/lib/fhir/operation.rb) as the
  # appropriate HTTP response, so controllers don't need to branch on status.
  def render_operation_result(result)
    return head :no_content if result.status == :no_content

    if result.outcome
      render json: result.outcome, status: result.status, content_type: FHIR_CONTENT_TYPE
      return
    end

    location = result.location_path ? "#{base_url}/#{result.location_path}" : nil
    render_fhir_resource(result.resource, status: result.status, location: location, version_id: result.version_id)
  end

  def base_url
    "#{request.protocol}#{request.host_with_port}"
  end
end
