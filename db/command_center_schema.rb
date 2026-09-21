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

ActiveRecord::Schema[8.1].define(version: 2026_09_18_140001) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "alerts", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.bigint "event_definition_id", null: false
    t.string "name", null: false
    t.string "role", null: false
    t.datetime "updated_at", null: false
    t.index ["event_definition_id"], name: "index_alerts_on_event_definition_id"
    t.index ["name"], name: "index_alerts_on_name"
  end

  create_table "event_definitions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "event_type", null: false
    t.string "group", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["group", "event_type"], name: "index_event_definitions_on_group_and_event_type"
    t.index ["name"], name: "index_event_definitions_on_name", unique: true
  end

  add_foreign_key "alerts", "event_definitions"
end
