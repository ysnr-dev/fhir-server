# A registered SMART Backend Services client (machine-to-machine),
# authenticating either with a shared secret (only its SHA-256 digest is
# stored; the raw secret is shown exactly once at registration -- see
# rake fhir:register_client) or with a registered JWKS via private_key_jwt
# client assertions (Fhir::ClientAssertion). A JWKS client has no secret.
class OauthClient < ApplicationRecord
  has_many :access_tokens, dependent: :delete_all

  # Returns [client, raw_secret]; raw_secret is nil for JWKS clients.
  def self.register(name:, scopes:, jwks: nil)
    if jwks
      [create!(id: SecureRandom.uuid, name: name, scopes: scopes, jwks: jwks), nil]
    else
      secret = SecureRandom.hex(32)
      [create!(id: SecureRandom.uuid, name: name, secret_digest: digest(secret), scopes: scopes), secret]
    end
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
end
