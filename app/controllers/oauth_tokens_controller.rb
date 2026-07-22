# POST /oauth/token -- SMART Backend Services token endpoint (OAuth2
# client_credentials). Client authentication: HTTP Basic or client_id /
# client_secret body params. Always public; errors follow RFC 6749 section 5.2.
class OauthTokensController < ApplicationController
  include OauthClientAuthentication

  before_action { response.set_header("Cache-Control", "no-store") }

  def create
    unless params[:grant_type] == "client_credentials"
      return oauth_error(:bad_request, "unsupported_grant_type",
                         "grant_type must be 'client_credentials', got #{params[:grant_type].inspect}")
    end

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

  private

  # No scope param -> everything the client is registered for; otherwise the
  # request must be a subset of the registration (no silent narrowing).
  def granted_scopes(client)
    requested = params[:scope].to_s.split
    return client.allowed_scopes if requested.empty?

    valid = requested.all? { |scope| Fhir::Scopes.valid?(scope) } && (requested - client.allowed_scopes).empty?
    valid ? requested : nil
  end
end
