# FHIR Bulk Data Export (Bulk Data Access IG v2.0.0): kick off an async NDJSON
# export at the system level (/$export) or across every patient compartment
# (/Patient/$export -- Group/$export is not supported, no Group resource
# exists yet), then poll/download/cancel the resulting job.
class BulkExportsController < ApplicationController
  include FhirAuditing # first, so halted (401/403) requests are audited too

  # POST /$export or /Patient/$export -- 202 Accepted, Content-Location points
  # at the status endpoint. Requires `Prefer: respond-async` per the IG.
  def kickoff
    unless respond_async?
      return render_bad_request('This operation requires the header "Prefer: respond-async"')
    end

    bulk_params = parse_kickoff_params
    return if bulk_params.nil? # already rendered 400

    return render_bad_request("Unsupported parameter(s): #{bulk_params.unsupported_params.join(', ')}") if
      bulk_params.unsupported_params.any? && !lenient_handling?

    return unless authorize_fhir_request!(scope_checks_for(bulk_params.types))
    return render_too_many_requests if concurrent_export_in_progress?

    @export = BulkExport.create!(
      id: SecureRandom.uuid,
      kind: params[:kind],
      status: "in_progress",
      types: bulk_params.types,
      since: bulk_params.since,
      output_format: bulk_params.output_format,
      transaction_time: Time.current,
      request_url: request.original_url,
      oauth_client_id: current_client_id
    )
    BulkExportJob.perform_later(@export.id)

    response.set_header("Content-Location", "#{base_url}/$export/status/#{@export.id}")
    head :accepted
  end

  # GET /$export/status/:id -- 202 while running, 200 with the completion
  # manifest, or an error status once failed.
  def status
    return unless authorize_fhir_request!([]) # authenticate only; no scope required to poll
    return render_not_found_export unless export_record && owns?(export_record)

    export_record.mark_stale_failed! if export_record.stale?

    case export_record.status
    when "in_progress" then render_in_progress
    when "completed" then render_manifest
    when "failed" then render_export_failed
    when "cancelled" then render_not_found_export
    end
  end

  # DELETE /$export/status/:id -- cancels a running export.
  def cancel
    return unless authorize_fhir_request!([])
    return render_not_found_export unless export_record && owns?(export_record)
    return render_not_found_export unless export_record.in_progress?

    export_record.update!(status: "cancelled")
    export_record.bulk_export_files.delete_all

    render_operation_outcome_single(status: :accepted, severity: "information", code: "informational", diagnostics: "Export cancelled")
  end

  # GET /$export/files/:id -- one NDJSON output file.
  def download
    return render_not_found_export unless file_record && file_record.bulk_export.completed?
    return unless authorize_fhir_request!([]) # authenticate first; scope depends on the file's resource type
    return render_not_found_export unless owns?(file_record.bulk_export)
    return render_forbidden([file_record.resource_type, :read]) if
      Fhir::Auth.enabled? && !@current_access_token.scope_set.allows?(file_record.resource_type, :read)

    send_data file_record.content,
              type: "application/fhir+ndjson",
              disposition: "inline",
              filename: "#{file_record.resource_type}.#{file_record.sequence}.ndjson"
  end

  private

  def respond_async?
    prefer_tokens.include?("respond-async")
  end

  def lenient_handling?
    prefer_tokens.include?("handling=lenient")
  end

  def prefer_tokens
    request.headers["Prefer"].to_s.split(",").map(&:strip)
  end

  def parse_kickoff_params
    parameters_body = nil
    if request.post?
      payload, parse_error = parse_body
      if parse_error
        render_bad_request(parse_error)
        return nil
      end
      unless payload["resourceType"] == "Parameters"
        render_bad_request("POST $export requires a Parameters resource body")
        return nil
      end
      parameters_body = payload
    end

    Fhir::BulkExportParams.parse(
      query_string: request.query_string,
      parameters_body: parameters_body,
      valid_types: Fhir::ResourceRegistry.types
    )
  rescue Fhir::BulkExportParams::InvalidParams => e
    render_operation_outcome_single(status: :bad_request, severity: "error", code: "value", diagnostics: e.message)
    nil
  end

  # No _type means "everything this client can read", which requires a
  # wildcard grant -- mirrors GET /_history's system-wide read check. A
  # patient-level export always includes the Patient resources themselves
  # (like Patient/:id/$everything's subject), so that scope is required too.
  def scope_checks_for(types)
    return [["*", :read]] if types.nil?

    checks = types.map { |type| [type, :read] }
    checks << ["Patient", :read] if params[:kind] == "patient" && !types.include?("Patient")
    checks
  end

  def concurrent_export_in_progress?
    scope = BulkExport.where(status: "in_progress", oauth_client_id: current_client_id)
    scope.find_each { |export| export.mark_stale_failed! if export.stale? }
    scope.exists?
  end

  def current_client_id
    @current_access_token&.oauth_client_id
  end

  def owns?(export)
    return true unless Fhir::Auth.enabled?

    export.oauth_client_id == current_client_id
  end

  def export_record
    @export ||= BulkExport.find_by(id: params[:id])
  end

  def file_record
    @file ||= BulkExportFile.find_by(id: params[:id])
  end

  def render_in_progress
    response.set_header("X-Progress", "in-progress (#{export_record.bulk_export_files.count} file(s) written)")
    response.set_header("Retry-After", "10")
    head :accepted
  end

  def render_manifest
    render json: {
      "transactionTime" => export_record.transaction_time.utc.iso8601(3),
      "request" => export_record.request_url,
      "requiresAccessToken" => Fhir::Auth.enabled?,
      "output" => export_record.bulk_export_files.order(:resource_type, :sequence).map do |file|
        { "type" => file.resource_type, "url" => "#{base_url}/$export/files/#{file.id}", "count" => file.resource_count }
      end,
      "error" => []
    }, status: :ok, content_type: "application/json"
  end

  def render_export_failed
    render_operation_outcome_single(
      status: :internal_server_error,
      severity: "error",
      code: "exception",
      diagnostics: export_record.error_message || "Export failed"
    )
  end

  def render_not_found_export
    render_operation_outcome_single(status: :not_found, severity: "error", code: "not-found", diagnostics: "No such export")
  end

  def render_too_many_requests
    response.set_header("Retry-After", "300")
    render_operation_outcome_single(
      status: :too_many_requests,
      severity: "error",
      code: "throttled",
      diagnostics: "Only one export may be in progress per client at a time"
    )
  end

  def audit_interaction
    action_name == "cancel" ? "delete" : "operation"
  end

  def audit_resource_type
    return "Patient" if action_name == "kickoff" && params[:kind] == "patient"
    return file_record&.resource_type if action_name == "download"

    nil
  end

  def audit_resource_id
    action_name == "kickoff" ? @export&.id : params[:id]
  end
end
