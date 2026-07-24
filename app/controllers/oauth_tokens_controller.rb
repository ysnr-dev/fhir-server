# POST /oauth/token -- the token endpoint for the supported flows:
#
#   client_credentials  SMART Backend Services (machine-to-machine).
#   authorization_code  Interactive standalone launch, PKCE required.
#   refresh_token       Rotation of a refresh token obtained via
#                       offline_access / online_access on the interactive flow.
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
    when "refresh_token" then refresh_token_grant
    else
      oauth_error(:bad_request, "unsupported_grant_type",
                  "grant_type must be 'client_credentials', 'authorization_code' or 'refresh_token', " \
                  "got #{params[:grant_type].inspect}")
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
    return revoke_and_reject(code, "Authorization code has already been used") if code.used?
    return oauth_error(:bad_request, "invalid_grant", "Authorization code expired") if code.expired?

    client, auth_error = authenticate_code_client(code)
    return oauth_error(:unauthorized, "invalid_client", auth_error) unless client

    return oauth_error(:bad_request, "invalid_grant", "redirect_uri does not match the authorization request") unless
      params[:redirect_uri].to_s == code.redirect_uri
    return oauth_error(:bad_request, "invalid_grant", "PKCE verification failed") unless
      code.pkce_valid?(params[:code_verifier])

    # Losing this race means another request redeemed the code first, which is
    # indistinguishable from a replay -- treat it as one.
    return revoke_and_reject(code, "Authorization code has already been used") unless code.consume!

    _record, raw_token = AccessToken.issue(
      client, scopes: code.scope_list, user: code.user, patient_id: code.patient_id, authorization_code: code
    )

    # offline_access / online_access in the consented scopes ask for a refresh
    # token (SMART App Launch). Backend Services never gets one.
    raw_refresh = nil
    if Fhir::Scopes.refresh_requested?(code.scope_list)
      _refresh, raw_refresh = RefreshToken.issue(
        client: client, user: code.user, patient_id: code.patient_id,
        scopes: code.scope_list, authorization_code: code
      )
    end

    render json: {
      access_token: raw_token,
      token_type: "bearer",
      expires_in: AccessToken::TTL.to_i,
      scope: code.scopes,
      refresh_token: raw_refresh,
      # SMART launch context: tells the app which patient the token is for,
      # so it does not have to guess or ask.
      patient: code.patient_id
    }.compact
  end

  def refresh_token_grant
    refresh = RefreshToken.authenticate(params[:refresh_token])
    return oauth_error(:bad_request, "invalid_grant", "Invalid refresh token") unless refresh

    # Replay first, as with authorization codes: a consumed refresh token
    # presented again means it leaked, and rotation guarantees the legitimate
    # client no longer holds it -- so the whole grant is revoked (OAuth 2.0
    # Security BCP section 4.14.2).
    return revoke_and_reject(refresh.authorization_code, "Refresh token has already been used") if refresh.used?
    return oauth_error(:bad_request, "invalid_grant", "Refresh token revoked") if refresh.revoked?
    return oauth_error(:bad_request, "invalid_grant", "Refresh token expired") if refresh.expired?

    client, auth_error = authenticate_owning_client(refresh.oauth_client)
    return oauth_error(:unauthorized, "invalid_client", auth_error) unless client

    # An explicit scope param may only narrow (RFC 6749 section 6). The
    # narrowing applies to the access token being minted, not to the grant:
    # the rotated refresh token keeps the originally consented scopes.
    scopes = narrowed_scopes(refresh)
    return oauth_error(:bad_request, "invalid_scope", "Requested scope exceeds the original grant") unless scopes

    # Losing this race means the token was redeemed concurrently -- a replay.
    return revoke_and_reject(refresh.authorization_code, "Refresh token has already been used") unless refresh.consume!

    _record, raw_token = AccessToken.issue(
      client, scopes: scopes, user: refresh.user, patient_id: refresh.patient_id,
      authorization_code: refresh.authorization_code
    )
    _rotated, raw_refresh = refresh.rotate!

    render json: {
      access_token: raw_token,
      token_type: "bearer",
      expires_in: AccessToken::TTL.to_i,
      scope: scopes.join(" "),
      refresh_token: raw_refresh,
      patient: refresh.patient_id
    }
  end

  # A public client has no secret to prove anything with -- PKCE already tied
  # the code to the browser session that started the flow, and possession of
  # the (rotating, single-use) refresh token carries the grant after that. A
  # confidential one authenticates normally, and must be the client the grant
  # was issued to.
  def authenticate_owning_client(client)
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

  def authenticate_code_client(code)
    authenticate_owning_client(code.oauth_client)
  end

  def revoke_and_reject(code, description)
    code.revoke_issued_tokens!
    oauth_error(:bad_request, "invalid_grant", description)
  end

  # nil when the request oversteps; the full original scopes when no scope
  # param is given. Narrowing shapes only the access token being minted --
  # the grant itself (and the rotated refresh token) keeps the original set.
  def narrowed_scopes(refresh)
    requested = params[:scope].to_s.split
    return refresh.scope_list if requested.empty?

    (requested - refresh.scope_list).empty? ? requested : nil
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
