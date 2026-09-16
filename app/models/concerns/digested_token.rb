# What AccessToken, RefreshToken and AuthorizationCode share: the credential is
# stored only as a digest (the raw value exists just long enough to be handed
# out), expires at a fixed instant, and carries a space-separated scope string.
module DigestedToken
  extend ActiveSupport::Concern

  included do
    class_attribute :digest_attribute, default: :token_digest, instance_writer: false
  end

  class_methods do
    def authenticate(raw)
      return nil if raw.blank?

      find_by(digest_attribute => OauthClient.digest(raw))
    end
  end

  def expired?
    expires_at <= Time.current
  end

  def scope_list
    scopes.split
  end
end
