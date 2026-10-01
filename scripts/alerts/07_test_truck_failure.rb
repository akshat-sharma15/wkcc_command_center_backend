# Scenario 1 - Truck Failure (vehicle.failure).
#   bin/rails runner scripts/alerts/07_test_truck_failure.rb
# Picks an in-transit POC vehicle carrying waybills (not TRK-102, which is
# reserved for the diversion scenario), publishes the incident through
# POST /api/v1/incidents/vehicle.failure, checks the enrichment, in-app +
# Slack delivery, primary/secondary assignment, then exercises
# acknowledge -> assign -> escalate -> resolve and verifies history is kept.
require_relative "support/scenario_helpers"
include ScenarioHelpers

puts "=" * 70
puts "SCENARIO 1 - TRUCK FAILURE"
puts "=" * 70

rule = AlertRule.active.find_by(name: "Incident: Truck Failure")
abort("Run scripts/data/seed_advanced_incidents.rb first") unless rule

open_vehicle_ids = Alert.where(alert_rule: rule, status: "open").pluck(:record_id)
vehicle = Vehicle.fleet_monitoring_poc.where.not(number: "TRK-102").where.not(id: open_vehicle_ids)
                 .joins(trips: :waybills).merge(Trip.status_in_transit).distinct.order(:number).first
abort("No in-transit POC vehicle with waybills - run scripts/data/add_100_vehicles.rb and seed_waybills.rb") unless vehicle

section "Trigger"
puts "  Vehicle #{vehicle.number} (id=#{vehicle.id})"
status, body = api(:post, "/api/v1/incidents/vehicle.failure",
                   { entity_id: vehicle.id, payload: { failure_type: "Engine overheating", estimated_repair_minutes: 90, reported_by: "driver" } })
check("POST /api/v1/incidents/vehicle.failure", status == 201, "HTTP #{status}")
alert = body&.dig("alerts", 0)
abort("  ✗ no alert created: #{body.inspect}") unless alert

incident = alert["incident"]
section "Alert ##{alert['id']} enrichment"
show :truck, incident.dig("vehicle", "number")
show :driver, [ incident.dig("driver", "name"), incident.dig("driver", "phone") ].compact.join(" · ")
show :route, incident.dig("route", "label")
show :current_hub, incident.dig("current_hub", "name")
show :destination, incident.dig("next_hub", "name")
show :planned_eta, incident["planned_eta"]
show :predicted_eta, incident["predicted_eta"]
show :delay_minutes, incident["delay_minutes"]
show :waybills, incident["waybill_count"]
show :packages, incident["package_count"]
show :orders, incident["order_count"]
show :revenue_risk, inr(incident["revenue_risk"])
show :sla_risk, incident["sla_risk"]
check("enriched with vehicle/driver/route/hubs", %w[vehicle driver route current_hub next_hub].all? { |k| incident[k].present? })
check("waybill/order impact computed", incident["waybill_count"].to_i.positive? && incident["order_count"].to_i.positive?)
check("revenue risk computed from declared values", !incident["revenue_risk"].nil?, incident.dig("revenue", "formula"))
check("assigned to primary", alert["assignment_level"] == "primary", alert.dig("assignee", "name"))
check("VehicleOperationEvent BREAKDOWN recorded", VehicleOperationEvent.where(vehicle_id: vehicle.id, event_type: "BREAKDOWN").where("occurred_at > ?", 5.minutes.ago).exists?)

section "Delivery"
report_delivery(alert["id"])

section "Lifecycle"
id = alert["id"]
status, body = api(:post, "/api/v1/alerts/#{id}/acknowledge")
check("acknowledge", status == 200 && body["status"] == "acknowledged", "acknowledged_by=#{body&.dig('acknowledged_by')}")
status, body = api(:post, "/api/v1/alerts/#{id}/assign", { assignee_type: "user", assignee_id: USER_ID })
check("assign (manual) -> in progress", status == 200 && body["assignment_level"] == "manual" && body["status"] == "in_progress")
status, body = api(:post, "/api/v1/alerts/#{id}/escalate")
check("escalate to secondary", status == 200 && body["assignment_level"] == "secondary" && body["status"] == "escalated", body&.dig("assignee", "name") || body&.dig("error"))
status, body = api(:post, "/api/v1/alerts/#{id}/resolve", { resolution_note: "Replacement vehicle assigned." })
check("resolve with note", status == 200 && body["status"] == "resolved" && body["resolution_note"] == "Replacement vehicle assigned.")
status, = api(:post, "/api/v1/alerts/#{id}/acknowledge")
check("resolved alert rejects further actions", status == 422)

status, body = api(:get, "/api/v1/alerts/#{id}")
check("history kept (alert not deleted)", status == 200 && body["history"].map { |h| h["action"] } == %w[acknowledged reassigned escalated resolved],
      body&.dig("history")&.map { |h| h["action"] }&.join(" -> "))
finish!
