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

ActiveRecord::Schema[8.1].define(version: 2026_09_24_100500) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "alert_rules", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "created_by_user_id"
    t.boolean "enabled", default: true, null: false
    t.bigint "event_definition_id"
    t.string "field"
    t.string "group"
    t.string "name", null: false
    t.string "notification_channels", default: [], null: false, array: true
    t.boolean "notify", default: false, null: false
    t.string "operator"
    t.bigint "recipient_id"
    t.string "recipient_type"
    t.string "severity", null: false
    t.string "trigger_type", default: "condition", null: false
    t.datetime "updated_at", null: false
    t.jsonb "value"
    t.index ["enabled"], name: "index_alert_rules_on_enabled"
    t.index ["event_definition_id"], name: "index_alert_rules_on_event_definition_id"
    t.index ["group"], name: "index_alert_rules_on_group"
    t.index ["trigger_type"], name: "index_alert_rules_on_trigger_type"
  end

  create_table "alerts", force: :cascade do |t|
    t.string "actual_value"
    t.bigint "alert_rule_id", null: false
    t.datetime "created_at", null: false
    t.string "expected_value"
    t.string "field", null: false
    t.string "group", null: false
    t.jsonb "metadata"
    t.bigint "record_id", null: false
    t.datetime "resolved_at"
    t.string "severity", null: false
    t.string "status", default: "open", null: false
    t.datetime "triggered_at", null: false
    t.datetime "updated_at", null: false
    t.index ["alert_rule_id", "group", "record_id"], name: "index_alerts_on_open_rule_group_record", unique: true, where: "((status)::text = 'open'::text)"
    t.index ["alert_rule_id"], name: "index_alerts_on_alert_rule_id"
    t.index ["group", "record_id"], name: "index_alerts_on_group_and_record_id"
    t.index ["group"], name: "index_alerts_on_group"
    t.index ["status"], name: "index_alerts_on_status"
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

  create_table "hub_operations_events", force: :cascade do |t|
    t.string "bay_reference"
    t.datetime "created_at", null: false
    t.string "dock_reference"
    t.string "event_type", null: false
    t.bigint "hub_id", null: false
    t.jsonb "metadata"
    t.datetime "occurred_at", null: false
    t.bigint "package_id"
    t.bigint "trip_id"
    t.datetime "updated_at", null: false
    t.bigint "vehicle_id"
    t.index ["event_type", "occurred_at"], name: "index_hub_operations_events_on_event_type_and_occurred_at"
    t.index ["hub_id", "occurred_at"], name: "index_hub_operations_events_on_hub_id_and_occurred_at"
    t.index ["hub_id"], name: "index_hub_operations_events_on_hub_id"
    t.index ["package_id"], name: "index_hub_operations_events_on_package_id"
    t.index ["trip_id"], name: "index_hub_operations_events_on_trip_id"
    t.index ["vehicle_id"], name: "index_hub_operations_events_on_vehicle_id"
  end

  create_table "hubs", force: :cascade do |t|
    t.string "alertable_fields", default: [], null: false, array: true
    t.boolean "allow_alerts", default: false, null: false
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

  create_table "notifications", force: :cascade do |t|
    t.bigint "alert_id", null: false
    t.integer "attempts", default: 0, null: false
    t.string "channel", null: false
    t.datetime "created_at", null: false
    t.datetime "delivered_at"
    t.text "error_message"
    t.string "external_reference"
    t.datetime "failed_at"
    t.text "message"
    t.jsonb "metadata"
    t.datetime "read_at"
    t.bigint "recipient_user_id", null: false
    t.string "status", default: "pending", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["alert_id"], name: "index_notifications_on_alert_id"
    t.index ["channel"], name: "index_notifications_on_channel"
    t.index ["recipient_user_id", "read_at"], name: "index_notifications_on_recipient_user_id_and_read_at"
    t.index ["recipient_user_id"], name: "index_notifications_on_recipient_user_id"
    t.index ["status"], name: "index_notifications_on_status"
  end

  create_table "orders", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "customer_reference"
    t.datetime "delivered_at"
    t.bigint "destination_hub_id"
    t.string "order_number", null: false
    t.bigint "origin_hub_id"
    t.integer "package_count", default: 0, null: false
    t.string "priority"
    t.datetime "promised_delivery_at"
    t.string "status", default: "pending", null: false
    t.decimal "total_weight", precision: 10, scale: 2
    t.datetime "updated_at", null: false
    t.index ["destination_hub_id"], name: "index_orders_on_destination_hub_id"
    t.index ["order_number"], name: "index_orders_on_order_number", unique: true
    t.index ["origin_hub_id"], name: "index_orders_on_origin_hub_id"
    t.index ["promised_delivery_at"], name: "index_orders_on_promised_delivery_at"
    t.index ["status"], name: "index_orders_on_status"
  end

  create_table "package_status_transitions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "from_status"
    t.bigint "location_id"
    t.string "location_type"
    t.datetime "occurred_at", null: false
    t.bigint "package_id", null: false
    t.string "to_status", null: false
    t.index ["location_type", "location_id"], name: "index_package_status_transitions_on_location"
    t.index ["package_id", "occurred_at"], name: "index_package_status_transitions_on_package_id_and_occurred_at"
    t.index ["package_id"], name: "index_package_status_transitions_on_package_id"
    t.index ["to_status"], name: "index_package_status_transitions_on_to_status"
  end

  create_table "packages", force: :cascade do |t|
    t.string "alertable_fields", default: [], null: false, array: true
    t.boolean "allow_alerts", default: false, null: false
    t.datetime "created_at", null: false
    t.integer "damaged_quantity", default: 0, null: false
    t.datetime "delivered_at"
    t.integer "expected_quantity", default: 0, null: false
    t.string "identifier", null: false
    t.bigint "location_id", null: false
    t.string "location_type", null: false
    t.bigint "order_id"
    t.datetime "promised_delivery_at"
    t.integer "received_quantity", default: 0, null: false
    t.integer "short_quantity", default: 0, null: false
    t.string "status", default: "pending", null: false
    t.bigint "trip_id"
    t.datetime "updated_at", null: false
    t.index ["delivered_at"], name: "index_packages_on_delivered_at"
    t.index ["identifier"], name: "index_packages_on_identifier", unique: true
    t.index ["location_type", "location_id"], name: "index_packages_on_location"
    t.index ["order_id"], name: "index_packages_on_order_id"
    t.index ["promised_delivery_at"], name: "index_packages_on_promised_delivery_at"
    t.index ["status"], name: "index_packages_on_status"
    t.index ["trip_id"], name: "index_packages_on_trip_id"
  end

  create_table "payment_dues", force: :cascade do |t|
    t.string "alertable_fields", default: [], null: false, array: true
    t.boolean "allow_alerts", default: false, null: false
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

  create_table "vehicle_operation_events", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "event_type", null: false
    t.jsonb "metadata"
    t.datetime "occurred_at", null: false
    t.bigint "trip_id"
    t.datetime "updated_at", null: false
    t.bigint "vehicle_id", null: false
    t.index ["event_type", "occurred_at"], name: "index_vehicle_operation_events_on_event_type_and_occurred_at"
    t.index ["trip_id", "occurred_at"], name: "index_vehicle_operation_events_on_trip_id_and_occurred_at"
    t.index ["trip_id"], name: "index_vehicle_operation_events_on_trip_id"
    t.index ["vehicle_id", "occurred_at"], name: "index_vehicle_operation_events_on_vehicle_id_and_occurred_at"
    t.index ["vehicle_id"], name: "index_vehicle_operation_events_on_vehicle_id"
  end

  create_table "vehicles", force: :cascade do |t|
    t.string "alertable_fields", default: [], null: false, array: true
    t.boolean "allow_alerts", default: false, null: false
    t.integer "capacity"
    t.datetime "created_at", null: false
    t.string "current_location"
    t.bigint "driver_id"
    t.decimal "fuel_efficiency_kmpl", precision: 6, scale: 2
    t.bigint "hub_id", null: false
    t.decimal "last_known_latitude", precision: 9, scale: 6
    t.decimal "last_known_longitude", precision: 9, scale: 6
    t.datetime "last_location_at"
    t.decimal "mileage_km", precision: 10, scale: 2
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
    t.string "alertable_fields", default: [], null: false, array: true
    t.boolean "allow_alerts", default: false, null: false
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

  add_foreign_key "alert_rules", "event_definitions"
  add_foreign_key "alerts", "alert_rules"
  add_foreign_key "hub_operations_events", "hubs"
  add_foreign_key "hub_operations_events", "packages"
  add_foreign_key "hub_operations_events", "trips"
  add_foreign_key "hub_operations_events", "vehicles"
  add_foreign_key "notifications", "alerts"
  add_foreign_key "orders", "hubs", column: "destination_hub_id"
  add_foreign_key "orders", "hubs", column: "origin_hub_id"
  add_foreign_key "package_status_transitions", "packages"
  add_foreign_key "packages", "orders"
  add_foreign_key "packages", "trips"
  add_foreign_key "trips", "hubs", column: "destination_hub_id"
  add_foreign_key "trips", "hubs", column: "origin_hub_id"
  add_foreign_key "trips", "vehicles"
  add_foreign_key "vehicle_operation_events", "trips"
  add_foreign_key "vehicle_operation_events", "vehicles"
  add_foreign_key "vehicles", "hubs"
  add_foreign_key "vehicles", "workforce_members", column: "driver_id"
  add_foreign_key "workforce_members", "hubs"
end
