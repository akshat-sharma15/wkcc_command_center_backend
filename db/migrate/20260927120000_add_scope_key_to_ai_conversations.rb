# Chart-scoped AI chat: a conversation started for one Superset chart must
# not be reusable for a different chart, or for the unscoped global chat.
# `scope_key` records what a conversation was opened against ("chart:123",
# or NULL for the global assistant) so the binding can be enforced when a
# conversation_id comes back from the browser - see
# AiConversation.find_or_create_for_scope!.
class AddScopeKeyToAiConversations < ActiveRecord::Migration[8.1]
  def change
    add_column :ai_conversations, :scope_key, :string
    add_index :ai_conversations, :scope_key
  end
end
