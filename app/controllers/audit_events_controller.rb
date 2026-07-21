# Read-only access to the server-generated audit trail (search + read; audit
# rows cannot be created or modified through the API). Reads of the audit
# trail itself are deliberately NOT re-audited -- the trail covers clinical
# data access, and self-auditing would only add noise.
class AuditEventsController < ApplicationController
  before_action -> { authorize_fhir_request!([["AuditEvent", :read]]) }

  DEFAULT_COUNT = 20
  MAX_COUNT = 100

  def index
    scope = filtered_scope
    return if scope.nil? # already rendered 400

    total = scope.count
    count = clamped(params[:_count], default: DEFAULT_COUNT, max: MAX_COUNT)
    offset = [params[:_offset].to_i, 0].max
    records = scope.order(occurred_at: :desc, id: :desc).limit(count).offset(offset)

    render_fhir_resource(searchset_bundle(records, total: total, count: count, offset: offset), status: :ok)
  end

  def show
    record = AuditEvent.find_by(id: params[:id])
    unless record
      return render_operation_outcome_single(
        status: :not_found, severity: "error", code: "not-found",
        diagnostics: "AuditEvent/#{params[:id]} not found"
      )
    end

    render_fhir_resource(record.to_fhir, status: :ok)
  end

  private

  # Supported search params: date (ge/le/gt/lt prefixes, repeatable),
  # agent (client id), entity-type, entity (Type/id), subtype.
  def filtered_scope
    scope = AuditEvent.all
    scope = scope.where(client_id: params[:agent]) if params[:agent].present?
    scope = scope.where(resource_type: params[:"entity-type"]) if params[:"entity-type"].present?
    scope = scope.where(interaction: params[:subtype]) if params[:subtype].present?

    if params[:entity].present?
      type, id = params[:entity].split("/", 2)
      scope = scope.where(resource_type: type, resource_id: id)
    end

    apply_date_clauses(scope)
  end

  # `date` is parsed from the raw query string so repeated occurrences
  # (date=ge...&date=le...) AND together like a normal FHIR search.
  def apply_date_clauses(scope)
    Array(Rack::Utils.parse_query(request.query_string)["date"]).reduce(scope) do |current, value|
      prefix, raw = value.match(/\A(ge|le|gt|lt)?(.+)\z/).captures
      instant = begin
        Time.iso8601(raw)
      rescue ArgumentError
        render_operation_outcome_single(
          status: :bad_request, severity: "error", code: "value",
          diagnostics: "Invalid date value #{value.inspect}: must be an ISO 8601 instant with an optional ge/le/gt/lt prefix"
        )
        return nil
      end

      case prefix
      when "le" then current.where("occurred_at <= ?", instant)
      when "lt" then current.where("occurred_at < ?", instant)
      when "gt" then current.where("occurred_at > ?", instant)
      else current.where("occurred_at >= ?", instant) # ge and bare values
      end
    end
  end

  def clamped(raw, default:, max:)
    value = raw.present? ? raw.to_i : default
    value = default if value <= 0
    [value, max].min
  end

  def searchset_bundle(records, total:, count:, offset:)
    links = [{ "relation" => "self", "url" => page_url(offset) }]
    links << { "relation" => "previous", "url" => page_url([offset - count, 0].max) } if offset.positive?
    links << { "relation" => "next", "url" => page_url(offset + count) } if offset + count < total

    {
      "resourceType" => "Bundle",
      "type" => "searchset",
      "total" => total,
      "link" => links,
      "entry" => records.map do |record|
        {
          "fullUrl" => "#{base_url}/AuditEvent/#{record.id}",
          "resource" => record.to_fhir,
          "search" => { "mode" => "match" }
        }
      end
    }
  end

  def page_url(offset)
    query = Rack::Utils.parse_query(request.query_string).merge("_offset" => offset)
    "#{base_url}/AuditEvent?#{Rack::Utils.build_query(query)}"
  end
end
