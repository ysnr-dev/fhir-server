# An opaque bearer token. Opaque + DB-backed (rather than a self-contained JWT)
# keeps revocation trivial and adds no dependencies; swap in JWT assertions
# (RS384 + JWKS) later without changing the enforcement side.
#
# Tokens minted by the interactive launch flows additionally carry a launch
# context: the patient (and, for the standalone patient launch, the User), or
# the practitioner and encounter of an EHR launch. Compartment filtering is
# switched on by patient/ grants together with a patient context (see
# Fhir::PatientContext and ApplicationController#access_context).
class AccessToken < ApplicationRecord
  include DigestedToken

  TTL = 1.hour

  belongs_to :oauth_client
  belongs_to :user, optional: true
  belongs_to :authorization_code, optional: true

  # Returns [record, raw_token].
  def self.issue(client, scopes:, user: nil, patient_id: nil, practitioner_id: nil, encounter_id: nil,
                 authorization_code: nil)
    raw = SecureRandom.hex(32)
    record = create!(
      oauth_client: client,
      user: user,
      patient_id: patient_id,
      practitioner_id: practitioner_id,
      encounter_id: encounter_id,
      authorization_code: authorization_code,
      token_digest: OauthClient.digest(raw),
      scopes: scopes.join(" "),
      expires_at: TTL.from_now
    )
    [record, raw]
  end

  def revoked?
    revoked_at.present?
  end

  def patient_context?
    patient_id.present?
  end

  def practitioner_context?
    practitioner_id.present?
  end

  # The FHIR resource the token acts as: the practitioner of an EHR launch, the
  # patient of a standalone launch, nothing for Backend Services.
  def fhir_user_reference
    return "Practitioner/#{practitioner_id}" if practitioner_context?
    return "Patient/#{patient_id}" if user_id.present? && patient_context?

    nil
  end

  def scope_set
    @scope_set ||= Fhir::Scopes.new(effective_scopes)
  end

  private

  # Fail closed: a patient/ scope only means anything alongside a patient launch
  # context. Without one there is nothing to filter against, so honouring the
  # scope would grant unrestricted reads -- exactly backwards. Likewise a user/
  # scope stands for "what this practitioner may access", so without a
  # practitioner it stands for nothing (this is what keeps a launch client's
  # client_credentials token from reaching the whole facility). Registration
  # already keeps the client kinds disjoint; this is the second line.
  def effective_scopes
    granted = scope_list
    granted = granted.grep_v(%r{\Apatient/}) unless patient_context?
    granted = granted.grep_v(%r{\Auser/}) unless practitioner_context?
    granted
  end
end
