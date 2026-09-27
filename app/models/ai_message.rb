# One turn of an AiConversation. `steps` (jsonb) carries the raw
# assistant-turn structure (including any function_call/function_result
# entries) needed to replay history to the Gemini Interactions API on the
# next turn - see GeminiClient#history_from.
class AiMessage < ApplicationRecord
  ROLES = %w[user assistant].freeze

  belongs_to :ai_conversation

  validates :role, presence: true, inclusion: { in: ROLES }
end
