# Serves the type-level and instance-level FHIR interactions for every resource
# type registered in Fhir::ResourceRegistry. The concrete type comes from the
# route's `defaults: { resource_type: ... }` (see config/routes.rb), so adding a
# resource requires no new controller.
class FhirResourcesController < ApplicationController
  before_action :set_record, only: %i[history vread]

  def index
    result = Fhir::Operation.search(resource_type, request.query_string, base_url: base_url)
    render_operation_result(result)
  end

  def show
    render_operation_result(Fhir::Operation.read(resource_type, params[:id]))
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

  def destroy
    render_operation_result(Fhir::Operation.delete(resource_type, params[:id]))
  end

  def history
    return render_not_found unless @record

    versions = Fhir::Repository.history(resource_type, @record.id)
    bundle = BundleBuilder.history(resource_id: @record.id, versions: versions, base_url: base_url, resource_type: resource_type)
    render_fhir_resource(bundle, status: :ok)
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

  def set_record
    model = Fhir::ResourceRegistry.entry_for(resource_type).fetch(:model)
    @record = model.find_by(id: params[:id])
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
