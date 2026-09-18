# A machine credential for service-to-service access to this API (external
# event submitters, future API clients). Tokens are generated with
# SecureRandom and shown in plaintext exactly once, at creation time; only a
# SHA-256 digest is ever persisted. This is deliberately NOT bcrypt: bcrypt's
# per-record salt exists specifically to prevent O(1) lookup by the hash,
# which is the opposite of what a bearer-token lookup needs.
class ApiClient < ApplicationRecord
  scope :active, -> { where(active: true) }

  validates :name, presence: true, uniqueness: true
  validates :token_digest, presence: true, uniqueness: true

  # Generates a new client + raw token. Returns [api_client, raw_token] since
  # the raw token is never persisted or retrievable again after this call.
  def self.create_with_token!(name:, scopes: [])
    raw_token = SecureRandom.hex(32)
    api_client = create!(
      name: name,
      scopes: scopes,
      token_digest: digest(raw_token)
    )
    [api_client, raw_token]
  end

  def self.digest(raw_token)
    Digest::SHA256.hexdigest(raw_token)
  end

  def self.authenticate(raw_token)
    return nil if raw_token.blank?

    active.find_by(token_digest: digest(raw_token))
  end

  def has_scope?(scope)
    scopes.include?(scope.to_s)
  end
end
