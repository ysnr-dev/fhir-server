# Remembers each used client-assertion jti until its exp so a captured JWT
# cannot be replayed (SMART Backend Services requirement). Expired rows are
# pruned opportunistically on registration.
class ClientAssertionJti < ApplicationRecord
  # Returns true when the jti was fresh; false when it was already used.
  def self.register(client_id, jti, expires_at)
    where("expires_at < ?", Time.current).delete_all

    create!(oauth_client_id: client_id, jti: jti, expires_at: expires_at, created_at: Time.current)
    true
  rescue ActiveRecord::RecordNotUnique
    false
  end
end
