class BundlesController < ApplicationController
  def create
    payload, parse_error = parse_body
    return render_bad_request(parse_error) if parse_error
    return render_bad_request("resourceType must be 'Bundle'") unless payload["resourceType"] == "Bundle"

    result = BundleProcessor.call(payload, base_url: base_url)
    render json: result.body, status: result.status, content_type: FhirResponse::FHIR_CONTENT_TYPE
  end
end
