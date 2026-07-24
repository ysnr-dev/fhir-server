# A single-use OAuth2 authorization code (RFC 6749 section 4.1) carrying the
# consented scopes and the patient launch context over to the token endpoint.
# Stored as a digest only, like AccessToken: the raw value exists just long
# enough to travel through the browser redirect.
class AuthorizationCode < ApplicationRecord
  # Short by design -- the code only has to survive one redirect hop.
  TTL = 5.minutes

  # PKCE code_verifier: 43-128 characters from the unreserved set (RFC 7636
  # section 4.1). Checked before hashing so a malformed verifier is rejected
  # outright rather than merely failing to match.
  VERIFIER_PATTERN = /\A[A-Za-z0-9\-._~]{43,128}\z/

  belongs_to :oauth_client
  belongs_to :user
  has_many :access_tokens, dependent: :nullify

  # Returns [record, raw_code].
  def self.issue(client:, user:, scopes:, redirect_uri:, code_challenge:, code_challenge_method: "S256")
    raw = SecureRandom.urlsafe_base64(32)
    record = create!(
      oauth_client: client,
      user: user,
      patient_id: user.patient_id,
      scopes: scopes.join(" "),
      redirect_uri: redirect_uri,
      code_challenge: code_challenge,
      code_challenge_method: code_challenge_method,
      code_digest: OauthClient.digest(raw),
      expires_at: TTL.from_now
    )
    [record, raw]
  end

  def self.authenticate(raw)
    return nil if raw.blank?

    find_by(code_digest: OauthClient.digest(raw))
  end

  def expired?
    expires_at <= Time.current
  end

  def used?
    used_at.present?
  end

  # Claims the code atomically: the UPDATE ... WHERE used_at IS NULL lets the
  # database settle a race between concurrent redemptions, so exactly one caller
  # sees true and the loser is treated as a replay.
  def consume!
    claimed = self.class.where(id: id, used_at: nil).update_all(used_at: Time.current) == 1
    reload if claimed
    claimed
  end

  def pkce_valid?(verifier)
    return false unless VERIFIER_PATTERN.match?(verifier.to_s)
    return false unless code_challenge_method == "S256"

    expected = Base64.urlsafe_encode64(OpenSSL::Digest::SHA256.digest(verifier), padding: false)
    ActiveSupport::SecurityUtils.secure_compare(code_challenge, expected)
  end

  # A replayed code means it leaked, so anything it already produced is suspect
  # (RFC 6749 section 4.1.2).
  def revoke_issued_tokens!
    access_tokens.where(revoked_at: nil).update_all(revoked_at: Time.current)
  end

  def scope_list
    scopes.split
  end
end
