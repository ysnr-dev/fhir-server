# The EHR launch context of SMART App Launch: which patient, encounter and
# practitioner an app is being opened for, minted by the EHR (fhir-client's
# backend, through the admin API) and redeemed once by the app at
# /oauth/authorize via the `launch` parameter.
#
# Stored as a digest like the other credentials. Bound to one client so a
# token handed to app A can never start app B, and single-use so a leaked URL
# cannot be replayed after the app has consumed it.
class LaunchContext < ApplicationRecord
  include DigestedToken
  include SingleUseToken

  # Long enough for the browser to load the app and follow its redirect to
  # /oauth/authorize; short enough that a stale karte tab does not keep a
  # usable launch around.
  TTL = 5.minutes

  belongs_to :oauth_client
  has_many :authorization_codes, dependent: :nullify

  # Returns [record, raw_token].
  def self.issue(client:, patient_id:, practitioner_id:, encounter_id: nil, need_patient_banner: false, issued_by: nil)
    raw = SecureRandom.hex(32)
    record = create!(
      oauth_client: client,
      patient_id: patient_id,
      encounter_id: encounter_id.presence,
      practitioner_id: practitioner_id,
      need_patient_banner: need_patient_banner,
      issued_by: issued_by.presence,
      token_digest: OauthClient.digest(raw),
      expires_at: TTL.from_now
    )
    [record, raw]
  end

  # DigestedToken#scope_list reads `scopes`, which a launch context does not
  # carry: the scopes are the app's to request at authorize time.
  def scope_list
    []
  end
end
