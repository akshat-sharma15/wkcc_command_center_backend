# Creates NEW incidents on demand, each of which sends the normal in-app + Slack
# notifications, and optionally assigns them to Superset users.
#
#   bin/rails runner scripts/trigger_incident_notifications.rb
#   ASSIGN_TO=3,4 bin/rails runner scripts/trigger_incident_notifications.rb
#   KINDS=truck,hub,diversion ASSIGN_TO=admin,alpha bin/rails runner scripts/trigger_incident_notifications.rb
#
# ENV (all optional):
#   ASSIGN_TO  comma list of Superset user ids, usernames or emails. Incidents are
#              assigned to them in turn (3 incidents, 2 users -> A, B, A). Unset = no
#              assignment; the rule's own recipients are notified as usual.
#   KINDS      comma list of what to create, default "truck,hub,truck":
#                truck      Truck Failure on a real in-transit truck that has waybills
#                hub        Extra Vehicle Request at a real hub
#                diversion  Route Diversion on an in-transit trip. It CREATES a real
#                           RouteDiversion record (changes trip/ETA data), so it is opt-in.
#
# Unlike scripts/demo_incident_notifications.rb (idempotent, reuses one fixed set), every
# run here creates fresh alerts, so each run sends fresh notifications. Nothing is
# deleted; run it as often as you like and resolve the incidents from the app.
#
# Everything goes through the real API (same code paths as the app), so assignment
# also sends the "assigned to X" notification to the assignee via IncidentLifecycleNotifier.
# Sidekiq must be running: it is what delivers the Slack and in-app messages.
require_relative "alerts/support/scenario_helpers"
include ScenarioHelpers

KIND_ALIASES = { "truck" => :truck, "hub" => :hub, "diversion" => :diversion }.freeze
kinds = ENV.fetch("KINDS", "truck,hub,truck").split(",").map { |k| KIND_ALIASES[k.strip] or abort("Unknown KINDS entry #{k.inspect}. Use: truck, hub, diversion") }

users = SupersetDirectory.users
abort("Superset is not configured here (no users found) - set the SUPERSET_PG* env vars first.") if users.empty?

assignees = ENV["ASSIGN_TO"].to_s.split(",").map(&:strip).reject(&:empty?).map do |ref|
  users.find { |u| u[:id].to_s == ref || u[:username].to_s.casecmp?(ref) || u[:email].to_s.casecmp?(ref) } ||
    abort("ASSIGN_TO=#{ref} matches no Superset user. Available: #{users.map { |u| "#{u[:id]}:#{u[:username]}" }.join(', ')}")
end

puts "=" * 70
puts "TRIGGER #{kinds.size} NEW INCIDENT(S)  assign_to=#{assignees.map { |u| u[:username] }.join(', ').presence || '(none)'}"
puts "=" * 70

def recent_open_ids(rule_name) = Alert.joins(:alert_rule).where(alert_rules: { name: rule_name }, status: Alert::ACTIVE_STATUSES).pluck(:record_id)

created = []

kinds.each_with_index do |kind, i|
  section "##{i + 1} #{kind}"
  alert_id =
    case kind
    when :truck
      vehicle = Vehicle.fleet_monitoring_poc.where.not(number: "TRK-102").where.not(id: recent_open_ids("Incident: Truck Failure"))
                       .joins(trips: :waybills).merge(Trip.status_in_transit).distinct.to_a.sample
      if vehicle
        puts "  vehicle #{vehicle.number}"
        status, body = api(:post, "/api/v1/incidents/vehicle.failure",
                           { entity_id: vehicle.id, payload: { failure_type: %w[Engine\ overheating Tyre\ burst Brake\ failure].sample, estimated_repair_minutes: [ 45, 60, 90, 120 ].sample, reported_by: "driver" } })
        check("POST vehicle.failure", status == 201, "HTTP #{status}")
        body&.dig("alerts", 0, "id")
      else
        puts "  ✗ no in-transit truck with waybills that has no open failure"
      end
    when :hub
      hub = Hub.joins(:vehicles).merge(Vehicle.fleet_monitoring_poc).where.not(id: recent_open_ids("Incident: Extra Vehicle Request")).distinct.to_a.sample
      if hub
        puts "  hub #{hub.code} #{hub.name}"
        status, body = api(:post, "/api/v1/incidents/hub.extra_vehicle_request",
                           { entity_id: hub.id, payload: { requested_vehicle_count: [ 1, 2, 3 ].sample, reason: "Outbound demand exceeds available capacity", needed_by: 4.hours.from_now.iso8601 } })
        check("POST hub.extra_vehicle_request", status == 201, "HTTP #{status}")
        body&.dig("alerts", 0, "id")
      else
        puts "  ✗ no hub without an open extra-vehicle request"
      end
    when :diversion
      trip = Trip.status_in_transit.joins(:vehicle).merge(Vehicle.fleet_monitoring_poc)
                 .where.not(id: RouteDiversion.active.select(:trip_id)).order(Arel.sql("RANDOM()")).first
      if trip
        puts "  trip ##{trip.id} #{trip.vehicle.number}"
        via = EtaImpactService.via_point(trip)&.dig(:name) || trip.destination_hub.geo_location&.city
        status, body = api(:post, "/api/v1/route-diversions", { vehicle_id: trip.vehicle_id, trip_id: trip.id, reason: "Highway closure", via_city: via })
        check("POST route-diversions", [ 200, 201 ].include?(status), "HTTP #{status}")
        body&.dig("alert", "id") || body&.dig("alerts", 0, "id")
      else
        puts "  ✗ no in-transit trip without an active diversion"
      end
    end
  next unless alert_id

  assignee = assignees.any? ? assignees[created.size % assignees.size] : nil
  if assignee
    status, body = api(:post, "/api/v1/alerts/#{alert_id}/assign", { assignee_type: "user", assignee_id: assignee[:id] })
    check("assigned to #{assignee[:username]}", status == 200 && body&.dig("assignee", "id") == assignee[:id], "status=#{body&.dig('status')}")
  end
  created << { id: alert_id, kind: kind, assignee: assignee }
end

abort("\nNothing was created.") if created.empty?

puts "\n  waiting for delivery…"
created.each { |c| wait_for_delivery(c[:id], timeout: 25) }

section "Result"
created.each do |c|
  rows = Notification.where(alert_id: c[:id])
  in_app = rows.where(channel: "in_app")
  slack = rows.where(channel: "slack")
  puts "  Alert ##{c[:id]} (#{c[:kind]})  assignee=#{c[:assignee]&.dig(:username) || '-'}  #{IncidentLinks.incident(c[:id])}"
  puts "      in-app: #{in_app.size} (#{in_app.group(:status).count})   slack: #{slack.size} (#{slack.group(:status).count})"
  slack.where(status: "failed").limit(2).each { |n| puts "      slack error: #{n.error_message}" }
end

puts "\n" + "=" * 70
puts $scenario_failures.to_i.zero? ? "✓ DONE - #{created.size} incident(s) created" : "✗ #{$scenario_failures} step(s) failed"
puts "=" * 70
