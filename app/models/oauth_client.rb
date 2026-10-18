# A registered OAuth2 client. Two shapes share this table:
#
#   * Backend Services (machine-to-machine): system/ scopes, client_credentials,
#     authenticating with a shared secret (only its SHA-256 digest is stored;
#     the raw secret is shown exactly once at registration -- see
#     rake fhir:register_client) or with a registered JWKS via private_key_jwt
#     client assertions (Fhir::ClientAssertion). A JWKS client has no secret.
#
#   * Interactive launch clients: patient/ scopes (standalone patient launch)
#     or user/ scopes (EHR launch on behalf of a practitioner), authorization_code
#     + PKCE, with one or more registered redirect URIs. Public ones (SPAs,
#     native apps) hold no secret -- PKCE is the proof of possession instead.
#
#   * Delegated clients (CDS Hooks services): user/ scopes and no redirect URI.
#     They never come to the token endpoint; the EHR obtains short-lived,
#     read-only tokens for them through the admin API (/admin/delegated_tokens)
#     and hands them over as fhirAuthorization.
#
# The kinds are kept disjoint by validation: a client is a system-scope backend
# client, a patient-scope launch client or a user-scope launch client, never a
# mix, so a compromised launch client can never present a token that skips
# compartment filtering, and a token's confinement follows from its grants alone.
class OauthClient < ApplicationRecord
  CLIENT_TYPES = %w[confidential public].freeze

  # 宣言順が意味を持つ: dependent はこの順に処理される。access_tokens と
  # refresh_tokens はどちらも authorization_codes を参照するため、
  # authorization_codes を先に消すとFK違反になる -- 必ず最後に置くこと。
  has_many :access_tokens, dependent: :delete_all
  has_many :refresh_tokens, dependent: :delete_all
  has_many :client_assertion_jtis, dependent: :delete_all
  # エクスポートの履歴自体は監査目的で残す(purge_bulk_exports が期限で回収する)。
  has_many :bulk_exports, dependent: :nullify
  has_many :launch_contexts, dependent: :delete_all
  has_many :authorization_codes, dependent: :delete_all

  # どちらもDBは null:false だが、presence 検証が無いと nil が
  # ActiveRecord::NotNullViolation(=500)になる。管理APIから直接叩かれるので、
  # 検証エラー(422)として扱えるようにしておく。
  validates :name, presence: true
  validates :scopes, presence: true
  validates :client_type, inclusion: { in: CLIENT_TYPES }
  validate :scopes_are_valid_and_not_mixed
  validate :launch_clients_have_redirect_uris
  validate :public_clients_hold_no_credentials

  # Returns [client, raw_secret]; raw_secret is nil for JWKS and public clients.
  def self.register(name:, scopes:, jwks: nil, redirect_uris: nil, client_type: "confidential")
    attributes = {
      id: SecureRandom.uuid,
      name: name,
      scopes: scopes,
      jwks: jwks,
      client_type: client_type,
      redirect_uris: Array(redirect_uris).join(" ").presence
    }

    return [create!(attributes), nil] if jwks || client_type == "public"

    secret = SecureRandom.hex(32)
    [create!(attributes.merge(secret_digest: digest(secret))), secret]
  end

  def self.authenticate(client_id, secret)
    return nil if client_id.blank? || secret.blank?

    client = find_by(id: client_id)
    return nil unless client&.secret_digest

    ActiveSupport::SecurityUtils.secure_compare(client.secret_digest, digest(secret)) ? client : nil
  end

  def self.digest(value)
    OpenSSL::Digest::SHA256.hexdigest(value)
  end

  def allowed_scopes
    scopes.split
  end

  def public_client?
    client_type == "public"
  end

  def launch_client?
    redirect_uri_list.any?
  end

  # Registering `launch` is the administrator's explicit opt-in to EHR launch:
  # only such a client can have a launch context minted for it.
  def ehr_launchable?
    launch_client? && allowed_scopes.include?("launch")
  end

  def user_scoped?
    allowed_scopes.any? { |scope| Fhir::Scopes.valid_user?(scope) }
  end

  # A CDS Hooks service: acts for a practitioner, but only through tokens the
  # EHR obtains for it -- it has no redirect URI to run an authorization from.
  def delegated_client?
    user_scoped? && !launch_client?
  end

  # The read part of the registered user/ scopes: what a delegated token may
  # carry. A CDS service reads to decide; writing goes through the clinician.
  def delegated_scopes
    allowed_scopes.filter_map do |scope|
      match = Fhir::Scopes::USER_PATTERN.match(scope)
      next unless match && Fhir::Scopes.access_for(match[2])&.include?(:read)

      "user/#{match[1]}.read"
    end.uniq
  end

  def redirect_uri_list
    redirect_uris.to_s.split
  end

  # Exact match only. Prefix or wildcard matching is what turns an authorization
  # endpoint into an open redirector, so there is deliberately no normalisation
  # here beyond what the client registered.
  def redirect_uri_registered?(uri)
    uri.present? && redirect_uri_list.include?(uri)
  end

  private

  def scopes_are_valid_and_not_mixed
    return if scopes.blank?

    granted = allowed_scopes
    unless granted.all? { |scope| Fhir::Scopes.valid?(scope) }
      return errors.add(:scopes, "contains an unsupported scope")
    end

    system = granted.any? { |scope| Fhir::Scopes.valid_system?(scope) }
    patient = granted.any? { |scope| Fhir::Scopes.valid_patient?(scope) }
    user = granted.any? { |scope| Fhir::Scopes.valid_user?(scope) }
    context = granted.any? { |scope| Fhir::Scopes.valid_context?(scope) }
    errors.add(:scopes, "cannot mix system/ and patient/ scopes") if system && patient
    errors.add(:scopes, "cannot mix system/ and user/ scopes") if system && user
    # A token's confinement is decided by whether it holds patient/ grants
    # (ApplicationController#access_context); a client holding both kinds would
    # make that answer depend on which scopes the app happened to request.
    errors.add(:scopes, "cannot mix patient/ and user/ scopes") if patient && user
    # The context scopes (offline/online_access, openid/fhirUser/profile, launch)
    # only mean anything in the interactive flow: a backend client mints its own
    # access tokens and has no user to identify. So they require a patient/ or
    # user/ scope alongside them -- on a system registration they are a mistake.
    errors.add(:scopes, "offline_access/openid/launch style scopes require patient/ or user/ scopes") if context && !(patient || user)
    # A delegated client holds no session of its own, so refresh/identity/launch mean nothing to it.
    errors.add(:scopes, "a user/ client without redirect URIs cannot take context scopes") if
      user && context && redirect_uri_list.empty?
  end

  def launch_clients_have_redirect_uris
    return if scopes.blank?

    patient = allowed_scopes.any? { |scope| Fhir::Scopes.valid_patient?(scope) }
    interactive = patient || user_scoped?
    # user/ without redirect URIs is a delegated client (CDS Hooks); patient/ has
    # no such form -- a patient always comes through the authorization endpoint.
    errors.add(:redirect_uris, "are required for patient/ scopes") if patient && redirect_uri_list.empty?
    errors.add(:scopes, "must be patient/ or user/ scopes for a redirect-based client") if !interactive && redirect_uri_list.any?
  end

  def public_clients_hold_no_credentials
    return unless public_client?

    errors.add(:secret_digest, "is not allowed for a public client") if secret_digest.present?
    errors.add(:jwks, "is not allowed for a public client") if jwks.present?
  end
end
