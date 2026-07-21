# Serves the type-level and instance-level FHIR interactions for every resource
# type registered in Fhir::ResourceRegistry. The concrete type comes from the
# route's `defaults: { resource_type: ... }` (see config/routes.rb), so adding a
# resource requires no new controller.
class FhirResourcesController < ApplicationController
  include FhirAuditing # first, so halted (401/403) requests are audited too

  before_action :authorize_interaction
  before_action :set_record, only: %i[history vread]

  # $validate computes without persisting and reveals nothing stored, so it
  # rides on the read scope alongside the other non-mutating interactions.
  WRITE_ACTIONS = %w[create update conditional_update patch_update destroy conditional_destroy].freeze

  # action_name -> restful-interaction code for the audit trail.
  AUDIT_INTERACTIONS = {
    "index" => "search-type",
    "show" => "read",
    "vread" => "vread",
    "history" => "history-instance",
    "type_history" => "history-type",
    "create" => "create",
    "update" => "update",
    "conditional_update" => "update",
    "patch_update" => "patch",
    "destroy" => "delete",
    "conditional_destroy" => "delete",
    "everything" => "operation",
    "validate" => "operation"
  }.freeze

  def index
    result = Fhir::Operation.search(resource_type, request.query_string, base_url: base_url)
    render_operation_result(result)
  end

  def show
    result = Fhir::Operation.read(resource_type, params[:id])

    # Conditional read: 304 with the current ETag and no body when the client's
    # cached copy is still current.
    if result.success? && not_modified?(result)
      response.set_header("ETag", %(W/"#{result.version_id}"))
      return head :not_modified
    end

    render_operation_result(result)
  end

  def create
    payload, parse_error = parse_body
    return render_bad_request(parse_error) if parse_error

    render_operation_result(
      Fhir::Operation.create(resource_type, payload, if_none_exist: request.headers["If-None-Exist"])
    )
  end

  def update
    payload, parse_error = parse_body
    return render_bad_request(parse_error) if parse_error

    render_operation_result(Fhir::Operation.update(resource_type, params[:id], payload, if_match: if_match_version))
  end

  # PUT /{type}?{criteria} -- conditional update. The raw query string is the
  # selection criteria (parsed strictly by Fhir::ConditionalMatch).
  def conditional_update
    payload, parse_error = parse_body
    return render_bad_request(parse_error) if parse_error

    render_operation_result(Fhir::Operation.conditional_update(resource_type, request.query_string, payload))
  end

  # PATCH /{type}/:id -- JSON Patch (RFC 6902) only; FHIRPath patch is not
  # supported, so any other media type is 415.
  def patch_update
    unless request.media_type == "application/json-patch+json"
      return render_operation_outcome_single(
        status: :unsupported_media_type,
        severity: "error",
        code: "not-supported",
        diagnostics: "PATCH requires Content-Type: application/json-patch+json"
      )
    end

    operations, parse_error = parse_patch_body
    return render_bad_request(parse_error) if parse_error

    render_operation_result(Fhir::Operation.patch(resource_type, params[:id], operations, if_match: if_match_version))
  end

  # POST /{type}/$validate -- validation without persistence. Accepts the
  # resource directly or wrapped in a Parameters resource (parameter "resource").
  def validate
    payload, parse_error = parse_body
    return render_bad_request(parse_error) if parse_error

    if payload["resourceType"] == "Parameters"
      payload = Array(payload["parameter"]).find { |p| p.is_a?(Hash) && p["name"] == "resource" }&.dig("resource")
      return render_bad_request("Parameters must contain a 'resource' parameter") unless payload.is_a?(Hash)
    end

    render_operation_result(Fhir::Operation.validate(resource_type, payload))
  end

  # GET /Patient/:id/$everything -- the patient compartment as one Bundle.
  def everything
    model = Fhir::ResourceRegistry.entry_for(resource_type).fetch(:model)
    record = model.find_by(id: params[:id])
    return render_not_found unless record
    return render_gone if record.deleted?

    since = parse_since_param
    return if since == :invalid # already rendered 400

    bundle = Fhir::PatientEverything.call(patient: record, base_url: base_url, types: type_filter_param, since: since)
    render_fhir_resource(bundle, status: :ok)
  rescue Fhir::PatientEverything::InvalidType => e
    render_operation_outcome_single(status: :bad_request, severity: "error", code: "value", diagnostics: e.message)
  end

  def destroy
    render_operation_result(Fhir::Operation.delete(resource_type, params[:id]))
  end

  # DELETE /{type}?{criteria} -- conditional delete (single-match only), same
  # criteria handling as conditional update.
  def conditional_destroy
    render_operation_result(Fhir::Operation.conditional_delete(resource_type, request.query_string))
  end

  def history
    return render_not_found unless @record

    versions = Fhir::Repository.history(resource_type, @record.id)
    bundle = BundleBuilder.history(resource_id: @record.id, versions: versions, base_url: base_url, resource_type: resource_type)
    render_fhir_resource(bundle, status: :ok)
  end

  # GET /{type}/_history -- history of every resource of this type, newest first.
  def type_history
    history_params = parse_history_params
    return if history_params.nil? # already rendered 400

    page = Fhir::Repository.type_history(
      resource_type, since: history_params.since, count: history_params.count, offset: history_params.offset
    )
    render_fhir_resource(
      BundleBuilder.history_page(page: page, base_url: base_url, path: "#{resource_type}/_history", params: history_params),
      status: :ok
    )
  end

  def vread
    return render_not_found unless @record

    version = Fhir::Repository.version(resource_type, @record.id, params[:vid].to_i)
    return render_not_found unless version
    return render_gone if version.deleted

    render_fhir_resource(
      Fhir::Meta.apply(version.content, version_id: version.version_id, last_updated: version.last_updated),
      status: :ok,
      version_id: version.version_id
    )
  end

  private

  def resource_type
    params[:resource_type]
  end

  def authorize_interaction
    return unless Fhir::Auth.enabled?

    access = WRITE_ACTIONS.include?(action_name) ? :write : :read
    authorize_fhir_request!([[resource_type, access]])
  end

  def audit_interaction
    AUDIT_INTERACTIONS[action_name]
  end

  def audit_resource_type
    resource_type
  end

  # The created resource's id only exists after the fact -- recover it from
  # the Location header ({base}/{type}/{id}/_history/{vid}).
  def audit_resource_id
    return params[:id] if params[:id].present?

    response.get_header("Location")&.match(%r{/#{resource_type}/([^/]+)/_history/})&.captures&.first
  end

  def set_record
    model = Fhir::ResourceRegistry.entry_for(resource_type).fetch(:model)
    @record = model.find_by(id: params[:id])
  end

  def if_match_version
    header = request.headers["If-Match"]
    return nil if header.blank?

    header.gsub(%r{^W/}, "").delete('"')
  end

  # If-None-Match takes precedence over If-Modified-Since (RFC 9110 section 13.1.3).
  def not_modified?(result)
    if_none_match = request.headers["If-None-Match"]
    if if_none_match.present?
      etag = if_none_match.gsub(%r{^W/}, "").delete('"').strip
      return etag == "*" || etag == result.version_id.to_s
    end

    threshold = parse_http_date(request.headers["If-Modified-Since"])
    return false unless threshold

    # HTTP dates carry second precision, so truncate before comparing --
    # otherwise sub-second lastUpdated fractions would always read as newer.
    Time.iso8601(result.resource.dig("meta", "lastUpdated")).change(usec: 0) <= threshold
  end

  def parse_http_date(header)
    return nil if header.blank?

    Time.httpdate(header)
  rescue ArgumentError
    nil
  end

  def type_filter_param
    raw = params[:_type]
    raw.present? ? raw.split(",").map(&:strip).reject(&:blank?) : nil
  end

  # Returns a Time, nil (absent), or :invalid after rendering the 400.
  def parse_since_param
    raw = params[:_since]
    return nil if raw.blank?

    Time.iso8601(raw)
  rescue ArgumentError
    render_operation_outcome_single(
      status: :bad_request,
      severity: "error",
      code: "value",
      diagnostics: "Invalid _since value #{raw.inspect}: must be an ISO 8601 instant"
    )
    :invalid
  end

  def render_not_found
    render_operation_outcome_single(
      status: :not_found,
      severity: "error",
      code: "not-found",
      diagnostics: "#{resource_type}/#{params[:id]} not found"
    )
  end

  def render_gone
    render_operation_outcome_single(
      status: :gone,
      severity: "error",
      code: "deleted",
      diagnostics: "#{resource_type}/#{params[:id]} has been deleted"
    )
  end
end
