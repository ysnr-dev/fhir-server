class OrganizationsController < ApplicationController
  RESOURCE_TYPE = "Organization".freeze

  before_action :set_organization, only: %i[history vread]

  def index
    result = Fhir::Operation.search(RESOURCE_TYPE, request.query_parameters, base_url: base_url)
    render_operation_result(result)
  end

  def show
    render_operation_result(Fhir::Operation.read(RESOURCE_TYPE, params[:id]))
  end

  def create
    payload, parse_error = parse_body
    return render_bad_request(parse_error) if parse_error

    render_operation_result(Fhir::Operation.create(RESOURCE_TYPE, payload))
  end

  def update
    payload, parse_error = parse_body
    return render_bad_request(parse_error) if parse_error

    render_operation_result(Fhir::Operation.update(RESOURCE_TYPE, params[:id], payload, if_match: if_match_version))
  end

  def destroy
    render_operation_result(Fhir::Operation.delete(RESOURCE_TYPE, params[:id]))
  end

  def history
    return render_not_found unless @organization

    versions = OrganizationRepository.history(@organization.id)
    bundle = BundleBuilder.history(resource_id: @organization.id, versions: versions, base_url: base_url, resource_type: RESOURCE_TYPE)
    render_fhir_resource(bundle, status: :ok)
  end

  def vread
    return render_not_found unless @organization

    version = OrganizationRepository.version(@organization.id, params[:vid].to_i)
    return render_not_found unless version
    return render_gone if version.deleted

    render_fhir_resource(
      Fhir::Meta.apply(version.content, version_id: version.version_id, last_updated: version.last_updated),
      status: :ok,
      version_id: version.version_id
    )
  end

  private

  def set_organization
    @organization = Organization.find_by(id: params[:id])
  end

  def parse_body
    body = request.body.read
    return [nil, "Request body must not be empty"] if body.blank?

    parsed = JSON.parse(body)
    return [nil, "Request body must be a JSON object"] unless parsed.is_a?(Hash)

    [parsed, nil]
  rescue JSON::ParserError => e
    [nil, "Malformed JSON: #{e.message}"]
  end

  def if_match_version
    header = request.headers["If-Match"]
    return nil if header.blank?

    header.gsub(%r{^W/}, "").delete('"')
  end

  def render_not_found
    render_operation_outcome_single(
      status: :not_found,
      severity: "error",
      code: "not-found",
      diagnostics: "Organization/#{params[:id]} not found"
    )
  end

  def render_gone
    render_operation_outcome_single(
      status: :gone,
      severity: "error",
      code: "deleted",
      diagnostics: "Organization/#{params[:id]} has been deleted"
    )
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
