# The browser-facing half of the SMART standalone launch: the authorization
# endpoint plus the login and consent steps behind it. Everything else in this
# app is an API controller; this one inherits ActionController::Base because it
# renders HTML, holds a session, and needs CSRF protection.
#
# The authorization request itself is NOT kept in the session. Its parameters
# ride along in hidden form fields and are re-validated in full on every POST,
# so several launches can be in flight in different tabs, and tampering only
# ever produces the same errors a fresh request would.
class Oauth::BrowserController < ActionController::Base
  layout "oauth"

  protect_from_forgery with: :exception

  before_action { response.set_header("Cache-Control", "no-store") }
  before_action :load_authorize_request

  AUTHORIZE_PARAMS = %w[client_id redirect_uri scope state code_challenge code_challenge_method].freeze

  # GET /oauth/authorize
  def authorize
    current_user ? render(:consent) : render(:login)
  end

  # POST /oauth/login
  def login
    user = User.authenticate(email: params[:email], password: params[:password])
    unless user
      Fhir::AuthThrottle.register_failure!(request.remote_ip)
      # Deliberately vague: distinguishing "no such account" from "wrong
      # password" would confirm which patients have accounts here.
      @error = "メールアドレスまたはパスワードが正しくありません"
      return render(:login, status: :unauthorized)
    end

    # New session id on privilege change (session fixation).
    reset_session
    session[:user_id] = user.id
    @current_user = user
    render :consent
  end

  # POST /oauth/consent
  def consent
    return render(:login, status: :unauthorized) unless current_user
    return redirect_with_error("access_denied", "The user denied the request") unless params[:decision] == "approve"

    _code, raw = AuthorizationCode.issue(
      client: @client,
      user: current_user,
      scopes: @scopes,
      redirect_uri: @redirect_uri,
      code_challenge: @code_challenge,
      code_challenge_method: @code_challenge_method
    )

    redirect_to_client(code: raw)
  end

  private

  # Validation happens in two stages, and the order matters.
  #
  # Stage 1 -- client_id and redirect_uri. If either is wrong we have no
  # trustworthy place to send the user, so the error is rendered here rather
  # than redirected. Redirecting on an unverified redirect_uri is exactly what
  # turns an authorization endpoint into an open redirector.
  #
  # Stage 2 -- everything else. The redirect_uri is now known-good, so errors
  # go back to the client as OAuth error parameters (RFC 6749 section 4.1.2.1).
  def load_authorize_request
    @client = OauthClient.find_by(id: params[:client_id])
    return render_request_error("Unknown client_id") unless @client&.launch_client?

    @redirect_uri = params[:redirect_uri].to_s
    return render_request_error("redirect_uri is not registered for this client") unless
      @client.redirect_uri_registered?(@redirect_uri)

    @state = params[:state].to_s
    @code_challenge = params[:code_challenge].to_s
    @code_challenge_method = params[:code_challenge_method].presence || "S256"

    return redirect_with_error("unsupported_response_type", "response_type must be 'code'") unless
      params[:response_type] == "code"
    # PKCE is required of every client, not just public ones: it costs a
    # confidential client nothing and removes a whole class of code-interception
    # attacks from the threat model.
    return redirect_with_error("invalid_request", "code_challenge is required") if @code_challenge.blank?
    return redirect_with_error("invalid_request", "code_challenge_method must be 'S256'") unless
      @code_challenge_method == "S256"

    @scopes = params[:scope].to_s.split
    return redirect_with_error("invalid_scope", "scope is required") if @scopes.empty?
    return redirect_with_error("invalid_scope", "Only patient/*.read style scopes are supported") unless
      @scopes.all? { |scope| Fhir::Scopes.valid_patient?(scope) }
    return redirect_with_error("invalid_scope", "Requested scope exceeds the client's registration") unless
      (@scopes - @client.allowed_scopes).empty?

    true
  end

  def current_user
    return @current_user if defined?(@current_user)

    @current_user = session[:user_id] && User.find_by(id: session[:user_id])
  end

  # The authorize parameters as they must be echoed back by the login and
  # consent forms.
  def authorize_fields
    AUTHORIZE_PARAMS.index_with { |name| params[name].to_s }
  end

  # Consent has to be informed, and "patient/Observation.read" is not something
  # a patient can be expected to read. Types not named here fall back to the
  # bare type, which is still better than the raw scope string.
  SCOPE_LABELS = {
    "*" => "すべての診療記録",
    "Patient" => "患者基本情報",
    "Observation" => "検査・バイタルの記録",
    "Condition" => "傷病名",
    "MedicationRequest" => "処方",
    "MedicationDispense" => "調剤",
    "MedicationStatement" => "服薬状況",
    "MedicationAdministration" => "投薬の実施記録",
    "AllergyIntolerance" => "アレルギー情報",
    "Immunization" => "予防接種歴",
    "Procedure" => "処置・手術",
    "Encounter" => "受診歴",
    "DiagnosticReport" => "検査レポート",
    "DocumentReference" => "文書",
    "Coverage" => "保険情報",
    "ServiceRequest" => "検査・処置の依頼",
    "Specimen" => "検体",
    "ImagingStudy" => "画像検査",
    "Composition" => "診療文書"
  }.freeze

  def scope_description(scope)
    type = scope[%r{\Apatient/([^.]+)\.}, 1]
    "#{SCOPE_LABELS.fetch(type, type)}の閲覧"
  end

  helper_method :authorize_fields, :current_user, :scope_description

  def redirect_to_client(**query)
    query = query.merge(state: @state).compact_blank
    separator = @redirect_uri.include?("?") ? "&" : "?"
    # allow_other_host: the whole point is to return to the client's own
    # origin, which was verified against the registration above.
    redirect_to("#{@redirect_uri}#{separator}#{query.to_query}", allow_other_host: true)
  end

  def redirect_with_error(error, description)
    redirect_to_client(error: error, error_description: description)
    false
  end

  def render_request_error(message)
    @message = message
    render :error, status: :bad_request
    false
  end
end
