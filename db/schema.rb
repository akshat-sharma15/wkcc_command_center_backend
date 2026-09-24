# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_09_24_180200) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "ai_conversations", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "last_message_at"
    t.string "session_key", null: false
    t.datetime "updated_at", null: false
    t.index ["session_key"], name: "index_ai_conversations_on_session_key", unique: true
  end

  create_table "ai_messages", force: :cascade do |t|
    t.bigint "ai_conversation_id", null: false
    t.text "content"
    t.datetime "created_at", null: false
    t.string "role", null: false
    t.jsonb "steps"
    t.index ["ai_conversation_id", "created_at"], name: "index_ai_messages_on_ai_conversation_id_and_created_at"
    t.index ["ai_conversation_id"], name: "index_ai_messages_on_ai_conversation_id"
  end

  create_table "ai_query_logs", force: :cascade do |t|
    t.bigint "ai_conversation_id"
    t.datetime "created_at", null: false
    t.text "error_message"
    t.float "execution_time_ms"
    t.string "model", null: false
    t.text "question", null: false
    t.integer "row_count"
    t.string "session_key", null: false
    t.string "source"
    t.jsonb "structured_query"
    t.boolean "success", null: false
    t.index ["ai_conversation_id"], name: "index_ai_query_logs_on_ai_conversation_id"
    t.index ["session_key"], name: "index_ai_query_logs_on_session_key"
    t.index ["source"], name: "index_ai_query_logs_on_source"
    t.index ["success"], name: "index_ai_query_logs_on_success"
  end

  create_table "api_clients", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "last_used_at"
    t.string "name", null: false
    t.string "scopes", default: [], null: false, array: true
    t.string "token_digest", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_api_clients_on_name", unique: true
    t.index ["token_digest"], name: "index_api_clients_on_token_digest", unique: true
  end

  add_foreign_key "ai_messages", "ai_conversations"
  add_foreign_key "ai_query_logs", "ai_conversations"
end
