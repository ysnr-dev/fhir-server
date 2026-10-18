# A single-use OAuth2 authorization code (RFC 6749 section 4.1) carrying the
# granted scopes and the launch context (patient, and either the consenting
# User or the launching practitioner and encounter) over to the token endpoint.
# Stored as a digest only, like AccessToken: the raw value exists just long
# enough to travel through the browser redirect.
class AuthorizationCode < ApplicationRecord
  include DigestedToken
  include SingleUseToken

  self.digest_attribute = :code_digest

  # Short by design -- the code only has to survive one redirect hop.
  TTL = 5.minutes

  # PKCE code_verifier: 43-128 characters from the unreserved set (RFC 7636
  # section 4.1). Checked before hashing so a malformed verifier is rejected
  # outright rather than merely failing to match.
  VERIFIER_PATTERN = /\A[A-Za-z0-9\-._~]{43,128}\z/

  belongs_to :oauth_client
  # A standalone launch is granted by a patient User; an EHR launch by a
  # practitioner the EHR vouched for, who has no User row here.
  belongs_to :user, optional: true
  belongs_to :launch_context, optional: true
  has_many :access_tokens, dependent: :nullify
  has_many :refresh_tokens, dependent: :destroy

  validate :granted_by_user_or_practitioner

  # Returns [record, raw_code]. The patient defaults to the consenting User's
  # own; an EHR launch names it (and the practitioner) explicitly.
  def self.issue(client:, scopes:, redirect_uri:, code_challenge:, code_challenge_method: "S256", nonce: nil,
                 user: nil, patient_id: nil, practitioner_id: nil, encounter_id: nil, launch_context: nil)
    raw = SecureRandom.urlsafe_base64(32)
    record = create!(
      oauth_client: client,
      user: user,
      patient_id: patient_id || user&.patient_id,
      practitioner_id: practitioner_id,
      encounter_id: encounter_id,
      launch_context: launch_context,
      scopes: scopes.join(" "),
      redirect_uri: redirect_uri,
      code_challenge: code_challenge,
      code_challenge_method: code_challenge_method,
      nonce: nonce.presence,
      code_digest: OauthClient.digest(raw),
      expires_at: TTL.from_now
    )
    [record, raw]
  end

  def pkce_valid?(verifier)
    return false unless VERIFIER_PATTERN.match?(verifier.to_s)
    return false unless code_challenge_method == "S256"

    expected = Base64.urlsafe_encode64(OpenSSL::Digest::SHA256.digest(verifier), padding: false)
    ActiveSupport::SecurityUtils.secure_compare(code_challenge, expected)
  end

  # A replayed code means it leaked, so anything it already produced is suspect
  # (RFC 6749 section 4.1.2). The same treatment applies when a rotated-out
  # refresh token is replayed -- the code anchors the whole grant either way.
  def revoke_issued_tokens!
    access_tokens.where(revoked_at: nil).update_all(revoked_at: Time.current)
    refresh_tokens.where(revoked_at: nil).update_all(revoked_at: Time.current)
  end

  private

  def granted_by_user_or_practitioner
    errors.add(:base, "must be granted by a user or a practitioner") if user.nil? && practitioner_id.blank?
  end
end
