# A short-lived, one-time-use CSRF token for the Slack OAuth handshake —
# see the migration for why this is DB-backed rather than session-based.
class SlackOauthState < CommandCenterRecord
  TTL = 10.minutes

  validates :state, presence: true, uniqueness: true
  validates :expires_at, presence: true

  def self.issue!
    create!(state: SecureRandom.hex(24), expires_at: TTL.from_now)
  end

  def expired?
    expires_at.past?
  end
end
