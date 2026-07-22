class ApplicationController < ActionController::API
  include FhirResponse

  rescue_from StandardError, with: :render_internal_error
  # Raised when Rails parses a malformed JSON body on first params access
  # (e.g. in an auth before_action); the client's error, not a 500.
  rescue_from ActionDispatch::Http::Parameters::ParseError do |e|
    render_bad_request("Malformed JSON: #{e.message}")
  end

  private

  # --- SMART Backend Services enforcement ------------------------------------

  # checks: array of [resource_type, :read | :write] pairs the request needs.
  # Returns true when the request may proceed; renders 401/403 (and returns
  # false) otherwise. A no-op when auth is disabled (Fhir::Auth).
  def authorize_fhir_request!(checks)
    return true unless Fhir::Auth.enabled?

    raw = bearer_token
    return render_unauthorized("Missing bearer token", error: nil) if raw.blank?

    token = AccessToken.authenticate(raw)
    return render_unauthorized("Invalid access token") unless token
    return render_unauthorized("Access token revoked") if token.revoked?
    return render_unauthorized("Access token expired", issue_code: "expired") if token.expired?

    # Remembered before the scope check so denied (403) requests are still
    # attributed to the client in the audit trail (FhirAuditing).
    @current_access_token = token

    denied = checks.find { |type, access| !token.scope_set.allows?(type, access) }
    denied ? render_forbidden(denied) : true
  end

  def bearer_token
    request.authorization&.match(/\ABearer\s+(.+)\z/i)&.captures&.first
  end

  # RFC 6750: 401 with WWW-Authenticate; the error attribute is omitted when no
  # credentials were presented at all.
  def render_unauthorized(description, error: "invalid_token", issue_code: "login")
    Fhir::AuthThrottle.register_failure!(request.remote_ip)
    challenge = %(Bearer realm="fhir-server")
    challenge += %(, error="#{error}", error_description="#{description}") if error
    response.set_header("WWW-Authenticate", challenge)
    render_operation_outcome_single(status: :unauthorized, severity: "error", code: issue_code, diagnostics: description)
    false
  end

  def render_forbidden((resource_type, access))
    render_operation_outcome_single(
      status: :forbidden,
      severity: "error",
      code: "forbidden",
      diagnostics: "Insufficient scope: this interaction requires system/#{resource_type}.#{access}"
    )
    false
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
