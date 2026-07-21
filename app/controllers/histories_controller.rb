# GET /_history -- system-level history across every resource type. Lives
# outside FhirResourcesController because that controller's actions all assume
# a single resource_type injected by the route defaults.
class HistoriesController < ApplicationController
  include FhirAuditing # first, so halted (401/403) requests are audited too

  # System-level history spans every resource type, so it needs a
  # wildcard-type read grant (system/*.read or system/*.*).
  before_action -> { authorize_fhir_request!([["*", :read]]) }

  def index
    history_params = parse_history_params
    return if history_params.nil? # already rendered 400

    page = Fhir::Repository.system_history(
      since: history_params.since, count: history_params.count, offset: history_params.offset
    )
    render_fhir_resource(
      BundleBuilder.history_page(page: page, base_url: base_url, path: "_history", params: history_params),
      status: :ok
    )
  end

  private

  def audit_interaction
    "history-system"
  end
end
