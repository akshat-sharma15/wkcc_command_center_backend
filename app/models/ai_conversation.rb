# A Command Centre AI chat session. `session_key` is the opaque
# `conversation_id` handed to/from the API - never a raw database id, so
# it can't be enumerated.
class AiConversation < ApplicationRecord
  has_many :ai_messages, -> { order(:created_at) }, dependent: :destroy
  has_many :ai_query_logs, dependent: :nullify

  validates :session_key, presence: true, uniqueness: true

  def self.find_or_create_by_session_key!(session_key)
    find_by(session_key: session_key) || create!(session_key: session_key || SecureRandom.urlsafe_base64(24))
  end

  def touch_last_message!
    update!(last_message_at: Time.current)
  end
end
