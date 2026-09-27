# Audit trail of every structured query the AI's `query_command_center`
# tool executed or attempted (approved and rejected alike - rejections
# are logged too, see CommandCenterQueryService). Never stores result
# rows, credentials, or the Gemini API key.
class AiQueryLog < ApplicationRecord
  belongs_to :ai_conversation, optional: true

  validates :session_key, presence: true
  validates :question, presence: true
  validates :model, presence: true
  validates :success, inclusion: { in: [ true, false ] }
end
