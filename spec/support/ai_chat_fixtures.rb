# Small, self-contained, real COMMITTED data for the Command Centre AI
# chatbot specs (query_service_spec, ai_chat_service_spec, api/v1/ai_spec).
#
# Why this exists: CommandCenter::QueryService executes through
# AiReadOnlyRecord, a genuinely separate Postgres connection/session from
# the one rspec-rails wraps in each example's rolled-back transaction. A
# record created with FactoryBot inside a normal `it` block is invisible
# to that other session (correct Postgres isolation - it was never
# committed). So these specs need data created OUTSIDE the per-example
# transaction and actually committed - hence `before(:context)`/
# `after(:context)`, not `before(:each)`.
#
# Deliberately NOT the full CommandCentreDemoSeed (that's ~15k rows and
# is meant to be loaded once for manual/Superset use, not per test file -
# an earlier attempt to reuse it here broke every OTHER spec that asserts
# exact record counts, e.g. "GET /api/v1/workforce_members returns
# exactly the 2 just-created records"). This fixture is sized to be
# self-cleaning within one spec file's context lifecycle so it never
# leaks into other files' examples.
module AiChatFixtures
  HUB_CODE_PREFIX = "AITEST-HUB-".freeze
  VEHICLE_NUMBER_PREFIX = "AITEST-VEH-".freeze

  Fixture = Struct.new(:indore_hub, :pune_hub, :vehicles, :trips, :orders, :packages, keyword_init: true)

  def self.seed!
    indore_hub = Hub.create!(code: "#{HUB_CODE_PREFIX}IND", name: "Indore AI-Test Hub", location: "Indore, MP",
      capacity: 500, parking_capacity: 40, available_parking: 2, operational_status: "degraded",
      allow_alerts: true, alertable_fields: %w[operational_status])
    pune_hub = Hub.create!(code: "#{HUB_CODE_PREFIX}PUN", name: "Pune AI-Test Hub", location: "Pune, MH",
      capacity: 400, parking_capacity: 30, available_parking: 20, operational_status: "active")

    v1 = Vehicle.create!(number: "#{VEHICLE_NUMBER_PREFIX}01", vehicle_type: "truck", status: "active",
      capacity: 2000, vendor: "Test Fleet Vendor", current_location: indore_hub.location, hub: indore_hub,
      mileage_km: 50_000, fuel_efficiency_kmpl: 5.0)
    v2 = Vehicle.create!(number: "#{VEHICLE_NUMBER_PREFIX}02", vehicle_type: "van", status: "maintenance",
      capacity: 1000, vendor: "Test Fleet Vendor", current_location: indore_hub.location, hub: indore_hub,
      mileage_km: 70_000, fuel_efficiency_kmpl: 8.0)
    v3 = Vehicle.create!(number: "#{VEHICLE_NUMBER_PREFIX}03", vehicle_type: "truck", status: "active",
      capacity: 5000, vendor: "Test Fleet Vendor", current_location: pune_hub.location, hub: pune_hub,
      mileage_km: 90_000, fuel_efficiency_kmpl: 3.0)
    v4 = Vehicle.create!(number: "#{VEHICLE_NUMBER_PREFIX}04", vehicle_type: "truck", status: "active",
      capacity: 3000, vendor: "Test Fleet Vendor", current_location: indore_hub.location, hub: indore_hub,
      mileage_km: 60_000, fuel_efficiency_kmpl: 6.0)
    vehicles = [ v1, v2, v3, v4 ]

    t_current = Trip.create!(vehicle: v4, origin_hub: indore_hub, destination_hub: pune_hub,
      departure_at: 2.hours.ago, expected_arrival_at: 2.hours.from_now, status: "in_transit",
      route_info: "Indore -> Pune")
    t_delayed = Trip.create!(vehicle: v1, origin_hub: pune_hub, destination_hub: indore_hub,
      departure_at: 2.days.ago, expected_arrival_at: 2.days.ago + 6.hours,
      actual_arrival_at: 2.days.ago + 10.hours, status: "delayed", route_info: "Pune -> Indore")
    t_completed = Trip.create!(vehicle: v3, origin_hub: indore_hub, destination_hub: pune_hub,
      departure_at: 5.days.ago, expected_arrival_at: 5.days.ago + 5.hours,
      actual_arrival_at: 5.days.ago + 5.hours + 10.minutes, status: "completed", route_info: "Indore -> Pune")
    trips = [ t_current, t_delayed, t_completed ]

    order_pending = Order.create!(order_number: "AITEST-ORD-001", status: "pending", origin_hub: indore_hub,
      destination_hub: pune_hub, package_count: 2, promised_delivery_at: 3.days.from_now)
    order_delivered = Order.create!(order_number: "AITEST-ORD-002", status: "delivered", origin_hub: pune_hub,
      destination_hub: indore_hub, package_count: 1, promised_delivery_at: 2.days.ago, delivered_at: 3.days.ago)
    orders = [ order_pending, order_delivered ]

    p_in_transit_1 = Package.create!(identifier: "AITEST-PKG-001", order: order_pending, trip: t_current,
      location: indore_hub, expected_quantity: 10, received_quantity: 10, status: "in_transit")
    p_in_transit_2 = Package.create!(identifier: "AITEST-PKG-002", order: order_pending, trip: t_current,
      location: indore_hub, expected_quantity: 5, received_quantity: 5, status: "in_transit")
    p_damaged = Package.create!(identifier: "AITEST-PKG-003", order: order_delivered, location: pune_hub,
      expected_quantity: 8, received_quantity: 6, damaged_quantity: 2, status: "damaged")
    p_delivered = Package.create!(identifier: "AITEST-PKG-004", order: order_delivered, location: indore_hub,
      expected_quantity: 4, received_quantity: 4, status: "delivered",
      promised_delivery_at: 3.days.ago, delivered_at: 2.days.ago)
    p_overdue = Package.create!(identifier: "AITEST-PKG-005", location: indore_hub,
      expected_quantity: 3, received_quantity: 0, status: "pending", promised_delivery_at: 2.days.ago)
    packages = [ p_in_transit_1, p_in_transit_2, p_damaged, p_delivered, p_overdue ]

    VehicleOperationEvent.create!(vehicle: v4, trip: t_current, event_type: "BREAKDOWN", occurred_at: 1.hour.ago)

    alert_rule = AlertRule.create!(name: "AITEST rule", trigger_type: "condition", group: "hubs", field: "operational_status",
      operator: "=", value: "degraded", severity: "critical", enabled: true)
    Alert.create!(alert_rule: alert_rule, group: "hubs", record_id: indore_hub.id, field: "operational_status",
      expected_value: "degraded", actual_value: "degraded", severity: "critical", status: "open", triggered_at: 1.hour.ago)

    Fixture.new(indore_hub: indore_hub, pune_hub: pune_hub, vehicles: vehicles, trips: trips, orders: orders, packages: packages)
  end

  def self.cleanup!
    alert_rule = AlertRule.find_by(name: "AITEST rule")
    if alert_rule
      Alert.where(alert_rule_id: alert_rule.id).delete_all
      alert_rule.destroy
    end
    VehicleOperationEvent.joins(:vehicle).where("vehicles.number LIKE ?", "#{VEHICLE_NUMBER_PREFIX}%").delete_all
    Package.where("identifier LIKE ?", "AITEST-PKG-%").delete_all
    Order.where("order_number LIKE ?", "AITEST-ORD-%").delete_all
    Trip.joins(:vehicle).where("vehicles.number LIKE ?", "#{VEHICLE_NUMBER_PREFIX}%").delete_all
    Vehicle.where("number LIKE ?", "#{VEHICLE_NUMBER_PREFIX}%").delete_all
    Hub.where("code LIKE ?", "#{HUB_CODE_PREFIX}%").delete_all
  end
end
