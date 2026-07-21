# A registered SMART Backend Services client (machine-to-machine). Only the
# SHA-256 digest of the secret is stored; the raw secret is shown exactly once
# at registration (see rake fhir:register_client).
class OauthClient < ApplicationRecord
  has_many :access_tokens, dependent: :delete_all

  # Returns [client, raw_secret].
  def self.register(name:, scopes:)
    secret = SecureRandom.hex(32)
    client = create!(id: SecureRandom.uuid, name: name, secret_digest: digest(secret), scopes: scopes)
    [client, secret]
  end

  def self.authenticate(client_id, secret)
    return nil if client_id.blank? || secret.blank?

    client = find_by(id: client_id)
    return nil unless client

    ActiveSupport::SecurityUtils.secure_compare(client.secret_digest, digest(secret)) ? client : nil
  end

  def self.digest(value)
    OpenSSL::Digest::SHA256.hexdigest(value)
  end

  def allowed_scopes
    scopes.split
  end
end
