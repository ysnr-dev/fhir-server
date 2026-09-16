# An opaque, rotating refresh token (RFC 6749 section 6) for the interactive
# launch flow only -- Backend Services has none, since a system client can
# always mint a fresh access token itself. Stored as a digest, like
# AccessToken and AuthorizationCode.
#
# Rotation: redeeming a refresh token consumes it and issues a replacement, so
# at most one descendant of each grant is live at a time. A consumed token
# presented again means it leaked (OAuth 2.0 Security BCP section 4.14.2), and
# is handled like an authorization-code replay: the entire grant -- every
# access and refresh token the code produced -- is revoked.
class RefreshToken < ApplicationRecord
  include DigestedToken
  include SingleUseToken

  # offline_access outlives the user's session; online_access is supposed to
  # last only while the user remains signed in. Tokens are not linked to any
  # server-side session, so "online" is approximated by a much shorter
  # lifetime. Rotation renews the window either way.
  OFFLINE_TTL = 30.days
  ONLINE_TTL = 12.hours

  belongs_to :oauth_client
  belongs_to :user
  belongs_to :authorization_code

  # Returns [record, raw_token].
  def self.issue(client:, user:, patient_id:, scopes:, authorization_code:)
    raw = SecureRandom.hex(32)
    ttl = scopes.include?("offline_access") ? OFFLINE_TTL : ONLINE_TTL
    record = create!(
      oauth_client: client,
      user: user,
      patient_id: patient_id,
      scopes: scopes.join(" "),
      authorization_code: authorization_code,
      token_digest: OauthClient.digest(raw),
      expires_at: ttl.from_now
    )
    [record, raw]
  end

  def revoked?
    revoked_at.present?
  end

  # The rotation replacement: same grant, same scopes, fresh lifetime.
  # Returns [record, raw_token].
  def rotate!
    self.class.issue(
      client: oauth_client,
      user: user,
      patient_id: patient_id,
      scopes: scope_list,
      authorization_code: authorization_code
    )
  end
end
