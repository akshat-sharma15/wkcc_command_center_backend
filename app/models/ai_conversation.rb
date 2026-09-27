# A Command Centre AI chat session. `session_key` is the opaque
# `conversation_id` handed to/from the API - never a raw database id, so
# it can't be enumerated.
class AiConversation < ApplicationRecord
  has_many :ai_messages, -> { order(:created_at) }, dependent: :destroy
  has_many :ai_query_logs, dependent: :nullify

  validates :session_key, presence: true, uniqueness: true

  def self.find_or_create_by_session_key!(session_key)
    find_or_create_for_scope!(session_key, nil)
  end

  # Reuses an existing conversation only when it was opened against the same
  # scope (`nil` for the global assistant, "chart:<id>" for a chart chat).
  # A conversation_id from a different scope is ignored rather than trusted,
  # so a chart's context can't leak into another chart's chat - or into the
  # global one - by replaying its id.
  def self.find_or_create_for_scope!(session_key, scope_key)
    existing = find_by(session_key: session_key) if session_key.present?
    return existing if existing && existing.scope_key == scope_key

    create!(session_key: SecureRandom.urlsafe_base64(24), scope_key: scope_key)
  end

  def touch_last_message!
    update!(last_message_at: Time.current)
  end
end
