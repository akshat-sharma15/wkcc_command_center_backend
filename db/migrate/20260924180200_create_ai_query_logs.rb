# Audit log of every structured query the AI's function-calling tool
# actually executed (or attempted) against the read-only operations data.
# Deliberately does NOT store result rows (only row_count) - "be careful
# about logging large result sets" - and never stores credentials/secrets.
class CreateAiQueryLogs < ActiveRecord::Migration[8.1]
  def change
    create_table :ai_query_logs do |t|
      t.references :ai_conversation, null: true, foreign_key: true
      t.string :session_key, null: false
      t.text :question, null: false
      t.string :source
      t.jsonb :structured_query
      t.string :model, null: false
      t.boolean :success, null: false
      t.text :error_message
      t.integer :row_count
      t.float :execution_time_ms

      t.datetime :created_at, null: false
    end

    add_index :ai_query_logs, :session_key
    add_index :ai_query_logs, :source
    add_index :ai_query_logs, :success
  end
end
