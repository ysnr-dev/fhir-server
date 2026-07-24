# An opaque bearer token. Opaque + DB-backed (rather than a self-contained JWT)
# keeps revocation trivial and adds no dependencies; swap in JWT assertions
# (RS384 + JWKS) later without changing the enforcement side.
#
# Tokens minted by the interactive launch flow additionally carry a user and a
# patient launch context; that context -- not the scope string alone -- is what
# switches on compartment filtering (see Fhir::PatientContext).
class AccessToken < ApplicationRecord
  TTL = 1.hour

  belongs_to :oauth_client
  belongs_to :user, optional: true
  belongs_to :authorization_code, optional: true

  # Returns [record, raw_token].
  def self.issue(client, scopes:, user: nil, patient_id: nil, authorization_code: nil)
    raw = SecureRandom.hex(32)
    record = create!(
      oauth_client: client,
      user: user,
      patient_id: patient_id,
      authorization_code: authorization_code,
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

  def revoked?
    revoked_at.present?
  end

  def patient_context?
    patient_id.present?
  end

  def scope_set
    @scope_set ||= Fhir::Scopes.new(effective_scopes)
  end

  private

  # Fail closed: a patient/ scope only means anything alongside a patient launch
  # context. Without one there is nothing to filter against, so honouring the
  # scope would grant unrestricted reads -- exactly backwards. Registration
  # already keeps the two client kinds disjoint; this is the second line.
  def effective_scopes
    granted = scopes.split
    patient_context? ? granted : granted.grep_v(%r{\Apatient/})
  end
end
