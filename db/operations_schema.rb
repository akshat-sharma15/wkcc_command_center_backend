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

ActiveRecord::Schema[8.1].define(version: 2026_09_18_133006) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "hubs", force: :cascade do |t|
    t.integer "available_parking"
    t.integer "capacity"
    t.string "code", null: false
    t.datetime "created_at", null: false
    t.string "location"
    t.string "name", null: false
    t.string "operational_status", default: "active", null: false
    t.integer "parking_capacity"
    t.datetime "updated_at", null: false
    t.index ["code"], name: "index_hubs_on_code", unique: true
    t.index ["operational_status"], name: "index_hubs_on_operational_status"
  end

  create_table "packages", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "damaged_quantity", default: 0, null: false
    t.integer "expected_quantity", default: 0, null: false
    t.string "identifier", null: false
    t.bigint "location_id", null: false
    t.string "location_type", null: false
    t.integer "received_quantity", default: 0, null: false
    t.integer "short_quantity", default: 0, null: false
    t.string "status", default: "pending", null: false
    t.bigint "trip_id"
    t.datetime "updated_at", null: false
    t.index ["identifier"], name: "index_packages_on_identifier", unique: true
    t.index ["location_type", "location_id"], name: "index_packages_on_location"
    t.index ["status"], name: "index_packages_on_status"
    t.index ["trip_id"], name: "index_packages_on_trip_id"
  end

  create_table "payment_dues", force: :cascade do |t|
    t.decimal "amount", precision: 12, scale: 2, null: false
    t.datetime "created_at", null: false
    t.date "due_date", null: false
    t.string "payment_status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.string "vendor", null: false
    t.index ["due_date"], name: "index_payment_dues_on_due_date"
    t.index ["payment_status"], name: "index_payment_dues_on_payment_status"
  end

  create_table "trips", force: :cascade do |t|
    t.datetime "actual_arrival_at"
    t.datetime "created_at", null: false
    t.datetime "departure_at"
    t.bigint "destination_hub_id", null: false
    t.datetime "expected_arrival_at"
    t.bigint "origin_hub_id", null: false
    t.text "route_info"
    t.string "status", default: "scheduled", null: false
    t.datetime "updated_at", null: false
    t.bigint "vehicle_id", null: false
    t.index ["departure_at"], name: "index_trips_on_departure_at"
    t.index ["destination_hub_id"], name: "index_trips_on_destination_hub_id"
    t.index ["origin_hub_id"], name: "index_trips_on_origin_hub_id"
    t.index ["status"], name: "index_trips_on_status"
    t.index ["vehicle_id"], name: "index_trips_on_vehicle_id"
  end

  create_table "vehicles", force: :cascade do |t|
    t.integer "capacity"
    t.datetime "created_at", null: false
    t.string "current_location"
    t.bigint "driver_id"
    t.bigint "hub_id", null: false
    t.string "number", null: false
    t.string "status", default: "active", null: false
    t.datetime "updated_at", null: false
    t.string "vehicle_type", null: false
    t.string "vendor"
    t.index ["driver_id"], name: "index_vehicles_on_driver_id"
    t.index ["hub_id"], name: "index_vehicles_on_hub_id"
    t.index ["number"], name: "index_vehicles_on_number", unique: true
    t.index ["status"], name: "index_vehicles_on_status"
  end

  create_table "warehouses", force: :cascade do |t|
    t.integer "capacity"
    t.string "code", null: false
    t.datetime "created_at", null: false
    t.string "location"
    t.string "name", null: false
    t.string "status", default: "active", null: false
    t.datetime "updated_at", null: false
    t.index ["code"], name: "index_warehouses_on_code", unique: true
    t.index ["status"], name: "index_warehouses_on_status"
  end

  create_table "workforce_members", force: :cascade do |t|
    t.string "attendance_status", default: "present", null: false
    t.datetime "created_at", null: false
    t.bigint "hub_id", null: false
    t.string "identifier", null: false
    t.string "name", null: false
    t.string "role_type", null: false
    t.string "shift"
    t.datetime "updated_at", null: false
    t.index ["attendance_status"], name: "index_workforce_members_on_attendance_status"
    t.index ["hub_id"], name: "index_workforce_members_on_hub_id"
    t.index ["identifier"], name: "index_workforce_members_on_identifier", unique: true
    t.index ["role_type"], name: "index_workforce_members_on_role_type"
  end

  add_foreign_key "packages", "trips"
  add_foreign_key "trips", "hubs", column: "destination_hub_id"
  add_foreign_key "trips", "hubs", column: "origin_hub_id"
  add_foreign_key "trips", "vehicles"
  add_foreign_key "vehicles", "hubs"
  add_foreign_key "vehicles", "workforce_members", column: "driver_id"
  add_foreign_key "workforce_members", "hubs"
end
