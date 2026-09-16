# A credential that may be redeemed once (AuthorizationCode, RefreshToken).
module SingleUseToken
  extend ActiveSupport::Concern

  def used?
    used_at.present?
  end

  # Claims the credential atomically: the UPDATE ... WHERE used_at IS NULL lets
  # the database settle a race between concurrent redemptions, so exactly one
  # caller sees true and the loser is treated as a replay.
  def consume!
    claimed = self.class.where(id: id, used_at: nil).update_all(used_at: Time.current) == 1
    reload if claimed
    claimed
  end
end
