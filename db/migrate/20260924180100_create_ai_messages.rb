# Append-only turn history per conversation, used both to render the chat
# and to reconstruct the Gemini Interactions API's `input` history on each
# follow-up turn (see GeminiClient). `steps` holds the raw structured turn
# (including any function_call/function_result steps) for the assistant
# role only - `content` alone isn't enough to replay tool-calling turns.
class CreateAiMessages < ActiveRecord::Migration[8.1]
  def change
    create_table :ai_messages do |t|
      t.references :ai_conversation, null: false, foreign_key: true
      t.string :role, null: false
      t.text :content
      t.jsonb :steps

      t.datetime :created_at, null: false
    end

    add_index :ai_messages, [ :ai_conversation_id, :created_at ]
  end
end
