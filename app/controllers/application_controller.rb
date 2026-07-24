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
  #
  # require_system: for interactions that inherently reach past a single patient
  # compartment (server-wide history, the audit trail, bulk export). Those can
  # never be satisfied by a patient-context token, and `patient/*.read` would
  # otherwise pass the wildcard check -- see Fhir::Scopes.
  def authorize_fhir_request!(checks, require_system: false)
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

    denied = checks.find do |type, access|
      require_system ? !token.scope_set.system_allows?(type, access) : !token.scope_set.allows?(type, access)
    end
    denied ? render_forbidden(denied, require_system: require_system) : true
  end

  # The patient compartment this request is confined to, or nil when it is not
  # confined at all (system token, or auth disabled). Everything downstream
  # treats nil as "no filtering", which is what keeps the Backend Services path
  # byte-for-byte unchanged.
  def access_context
    return @access_context if defined?(@access_context)

    token = @current_access_token
    @access_context =
      if token&.patient_context?
        Fhir::PatientContext.new(patient_id: token.patient_id, scope_set: token.scope_set)
      end
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

  def render_forbidden((resource_type, access), require_system: false)
    render_operation_outcome_single(
      status: :forbidden,
      severity: "error",
      code: "forbidden",
      diagnostics: "Insufficient scope: this interaction requires #{required_scope(resource_type, access, require_system)}"
    )
    false
  end

  # Name the scope the caller could actually have asked for: a patient-context
  # token cannot obtain system/ scopes, so quoting them back would be a dead end
  # -- except on the system-only interactions, where that really is the answer.
  def required_scope(resource_type, access, require_system)
    if !require_system && @current_access_token&.patient_context?
      "patient/#{resource_type}.#{access}"
    else
      "system/#{resource_type}.#{access}"
    end
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
    # rescue_from が全例外を握るためSentryのRackミドルウェアには届かない。
    # ここで明示的に送る(DSN未設定ならSentry.initされておらずno-op)。
    Sentry.capture_exception(exception) if defined?(Sentry) && Sentry.initialized?
    Rails.logger.error("#{exception.class}: #{exception.message}\n#{exception.backtrace&.first(10)&.join("\n")}")
    render_operation_outcome_single(
      status: :internal_server_error,
      severity: "error",
      code: "exception",
      diagnostics: Rails.env.production? ? "An internal error occurred" : exception.message
    )
  end
end
