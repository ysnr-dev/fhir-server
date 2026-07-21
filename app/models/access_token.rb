# An opaque bearer token issued via client_credentials. Opaque + DB-backed
# (rather than a self-contained JWT) keeps revocation trivial and adds no
# dependencies; swap in JWT assertions (RS384 + JWKS) later without changing
# the enforcement side.
class AccessToken < ApplicationRecord
  TTL = 1.hour

  belongs_to :oauth_client

  # Returns [record, raw_token].
  def self.issue(client, scopes:)
    raw = SecureRandom.hex(32)
    record = create!(
      oauth_client: client,
      token_digest: OauthClient.digest(raw),
      scopes: scopes.join(" "),
      expires_at: TTL.from_now
    )
    [record, raw]
  end

  def self.authenticate(raw)
    return nil if raw.blank?

    find_by(token_digest: OauthClient.digest(raw))
  end

  def expired?
    expires_at <= Time.current
  end

  def scope_set
    @scope_set ||= Fhir::Scopes.new(scopes.split)
  end
end
