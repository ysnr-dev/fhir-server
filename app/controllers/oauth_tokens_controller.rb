# POST /oauth/token -- the token endpoint for both supported flows:
#
#   client_credentials  SMART Backend Services (machine-to-machine).
#   authorization_code  Interactive standalone launch, PKCE required.
#
# Client authentication: private_key_jwt, HTTP Basic, or client_id /
# client_secret body params -- except for public clients, where PKCE stands in
# for a secret the app could not keep. Always public; errors follow RFC 6749
# section 5.2.
class OauthTokensController < ApplicationController
  include OauthClientAuthentication

  before_action { response.set_header("Cache-Control", "no-store") }

  def create
    case params[:grant_type]
    when "client_credentials" then client_credentials_grant
    when "authorization_code" then authorization_code_grant
    else
      oauth_error(:bad_request, "unsupported_grant_type",
                  "grant_type must be 'client_credentials' or 'authorization_code', got #{params[:grant_type].inspect}")
    end
  end

  private

  def client_credentials_grant
    client, auth_error = resolve_client
    unless client
      response.set_header("WWW-Authenticate", %(Basic realm="fhir-server")) if basic_credentials
      return oauth_error(:unauthorized, "invalid_client", auth_error)
    end

    scopes = granted_scopes(client)
    return oauth_error(:bad_request, "invalid_scope", "Requested scope exceeds the client's registration") unless scopes

    _record, raw_token = AccessToken.issue(client, scopes: scopes)
    render json: {
      access_token: raw_token,
      token_type: "bearer",
      expires_in: AccessToken::TTL.to_i,
      scope: scopes.join(" ")
    }
  end

  def authorization_code_grant
    code = AuthorizationCode.authenticate(params[:code])
    return oauth_error(:bad_request, "invalid_grant", "Invalid authorization code") unless code

    # Replay check first, and it revokes rather than merely refusing: a second
    # presentation means the code leaked, so whatever it already produced is in
    # the attacker's hands too (RFC 6749 section 4.1.2).
    return revoke_and_reject(code) if code.used?
    return oauth_error(:bad_request, "invalid_grant", "Authorization code expired") if code.expired?

    client, auth_error = authenticate_code_client(code)
    return oauth_error(:unauthorized, "invalid_client", auth_error) unless client

    return oauth_error(:bad_request, "invalid_grant", "redirect_uri does not match the authorization request") unless
      params[:redirect_uri].to_s == code.redirect_uri
    return oauth_error(:bad_request, "invalid_grant", "PKCE verification failed") unless
      code.pkce_valid?(params[:code_verifier])

    # Losing this race means another request redeemed the code first, which is
    # indistinguishable from a replay -- treat it as one.
    return revoke_and_reject(code) unless code.consume!

    _record, raw_token = AccessToken.issue(
      client, scopes: code.scope_list, user: code.user, patient_id: code.patient_id, authorization_code: code
    )
    render json: {
      access_token: raw_token,
      token_type: "bearer",
      expires_in: AccessToken::TTL.to_i,
      scope: code.scopes,
      # SMART launch context: tells the app which patient the token is for,
      # so it does not have to guess or ask.
      patient: code.patient_id
    }
  end

  # A public client has no secret to prove anything with -- PKCE already ties
  # this request to the browser session that started the flow. A confidential
  # one authenticates normally, and must be the client the code was issued to.
  def authenticate_code_client(code)
    client = code.oauth_client

    if client.public_client?
      return [nil, "Client authentication failed"] unless params[:client_id].to_s == client.id

      @audited_client = client
      return [client, nil]
    end

    authenticated, auth_error = resolve_client
    return [nil, auth_error] unless authenticated
    return [nil, "Client authentication failed"] unless authenticated.id == client.id

    [client, nil]
  end

  def revoke_and_reject(code)
    code.revoke_issued_tokens!
    oauth_error(:bad_request, "invalid_grant", "Authorization code has already been used")
  end

  # No scope param -> everything the client is registered for; otherwise the
  # request must be a subset of the registration (no silent narrowing).
  def granted_scopes(client)
    requested = params[:scope].to_s.split
    return client.allowed_scopes if requested.empty?

    valid = requested.all? { |scope| Fhir::Scopes.valid?(scope) } && (requested - client.allowed_scopes).empty?
    valid ? requested : nil
  end
end
