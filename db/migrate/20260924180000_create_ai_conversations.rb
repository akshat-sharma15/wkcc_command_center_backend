# Command Centre AI chatbot (Phase 5). Lives in the `primary` database
# (cross-cutting app tables, alongside ApiClient) - conversations aren't
# operational/analytics data, they're app-level state, and must never be
# confused with the read-only operations-DB sources the chatbot queries.
class CreateAiConversations < ActiveRecord::Migration[8.1]
  def change
    create_table :ai_conversations do |t|
      t.string :session_key, null: false
      t.datetime :last_message_at

      t.timestamps
    end

    add_index :ai_conversations, :session_key, unique: true
  end
end
