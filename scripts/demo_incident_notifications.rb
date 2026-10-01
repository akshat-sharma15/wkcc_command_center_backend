# End-to-end demo: incident assignment + notifications across three
# incidents and two Superset users.
#
#   DEMO_USER_A=3 DEMO_USER_B=4 bin/rails runner scripts/demo_incident_notifications.rb
#
# USER IDS ARE CONFIGURATION, NEVER SEEDED. Create the two demo users in
# the Superset UI yourself, then pass their real ids (or usernames/emails)
# in DEMO_USER_A / DEMO_USER_B. Nothing here writes to Superset's tables
# or copies a Superset user into the operations database - users are only
# ever READ through SupersetDirectory, the same way AlertRecipientResolver
# and the alert-assignment endpoint do.
#
# Everything below runs through the real HTTP stack (routing, controllers,
# serializers), reusing the existing services end to end:
#   IncidentPublisher / RouteDiversionsController  -> creates the Alert
#   AlertNotifier                                  -> first fan-out
#   AlertsController assign/acknowledge/resolve    -> lifecycle + history
#   IncidentLifecycleNotifier                      -> tells the assignee
#   NotificationDeliveryJob                        -> in-app + Slack
#   RealtimeNotificationPublisher / SlackIncidentSyncJob -> live updates
#
# IDEMPOTENT: each of the three incidents is looked up by its own stable
# demo marker (metadata.incident.demo_ref) before anything is published,
# so re-running reuses the same three Alerts instead of creating more.
require_relative "alerts/support/scenario_helpers"
include ScenarioHelpers

DEMO_REFS = { diversion: "demo:route.diversion", failure: "demo:vehicle.failure", extra: "demo:hub.extra_vehicle_request" }.freeze

puts "=" * 70
puts "DEMO - INCIDENT ASSIGNMENT + NOTIFICATIONS"
puts "=" * 70

# ---------------------------------------------------------------- users
# Accepts an id, username or email so you can paste whatever the Superset
# UI shows you.
def resolve_demo_user(value, label)
  return nil if value.blank?

  users = SupersetDirectory.users
  user = users.find { |u| u[:id].to_s == value.to_s } ||
         users.find { |u| u[:username].to_s.casecmp?(value.to_s) } ||
         users.find { |u| u[:email].to_s.casecmp?(value.to_s) }
  abort("#{label}=#{value} does not match any Superset user. Available: #{users.map { |u| "#{u[:id]}:#{u[:username]}" }.join(', ')}") unless user
  user
end

admin = SupersetDirectory.users.find { |u| u[:username] == "admin" } || SupersetDirectory.users.first
abort("No Superset users found - is Superset configured?") unless admin

user_a = resolve_demo_user(ENV["DEMO_USER_A"], "DEMO_USER_A")
user_b = resolve_demo_user(ENV["DEMO_USER_B"], "DEMO_USER_B")

section "Demo users (read from Superset, never created here)"
show :admin, "#{admin[:id]} · #{admin[:username]} · #{admin[:email]}"
show :user_a, user_a ? "#{user_a[:id]} · #{user_a[:username]} · #{user_a[:email]}" : "— not set (DEMO_USER_A)"
show :user_b, user_b ? "#{user_b[:id]} · #{user_b[:username]} · #{user_b[:email]}" : "— not set (DEMO_USER_B)"

if user_a.nil? || user_b.nil?
  puts "\n  Create the two users in the Superset UI, then re-run with their ids:"
  puts "    DEMO_USER_A=<id> DEMO_USER_B=<id> bin/rails runner scripts/demo_incident_notifications.rb"
  puts "\n  Available Superset users right now:"
  SupersetDirectory.users.each { |u| puts "    id=#{u[:id]}  #{u[:username]}  #{u[:email]}" }
  abort("\n  Aborting: both DEMO_USER_A and DEMO_USER_B are required.")
end

# ------------------------------------------------------------ incidents
# Stamps a stable marker on the alert so a re-run finds this exact demo
# incident instead of publishing another one.
def mark_demo(alert_id, ref)
  alert = Alert.find(alert_id)
  incident = (alert.metadata["incident"] || {}).merge("demo_ref" => ref)
  alert.update_columns(metadata: alert.metadata.merge("incident" => incident)) # rubocop:disable Rails/SkipsModelValidations
  alert
end

def find_demo_alert(ref)
  Alert.where("alerts.metadata -> 'incident' ->> 'demo_ref' = ?", ref).where.not(status: "resolved").order(:id).first
end

def existing_or_publish(ref, label)
  existing = find_demo_alert(ref)
  if existing
    puts "  reusing Alert ##{existing.id} (#{label}) - idempotent"
    return existing
  end
  alert_id = yield
  return nil unless alert_id

  mark_demo(alert_id, ref).tap { puts "  created Alert ##{alert_id} (#{label})" }
end

section "Incident A - Route Diversion"
diversion_alert = existing_or_publish(DEMO_REFS[:diversion], "route diversion") do
  # Prefer an already-active diversion, exactly as asked; only publish a
  # new one if none exists.
  active = RouteDiversion.active.where.not(alert_id: nil).order(:id).first
  if active
    puts "  using existing active RouteDiversion ##{active.id} on #{active.vehicle.number}"
    active.alert_id
  else
    trip = Trip.status_in_transit.joins(:vehicle).merge(Vehicle.fleet_monitoring_poc)
               .where.not(id: RouteDiversion.active.select(:trip_id)).order(:id).first
    if trip.nil?
      puts "  ✗ no in-transit POC trip available for a diversion"
      nil
    else
      via = EtaImpactService.via_point(trip)&.dig(:name) || trip.destination_hub.geo_location&.city
      status, body = api(:post, "/api/v1/route-diversions",
                         { vehicle_id: trip.vehicle_id, trip_id: trip.id, reason: "Highway closure (demo)", via_city: via })
      check("POST /api/v1/route-diversions", [ 200, 201 ].include?(status), "HTTP #{status}")
      body&.dig("alert", "id") || body&.dig("alerts", 0, "id")
    end
  end
end

section "Incident B - Truck Failure"
failure_alert = existing_or_publish(DEMO_REFS[:failure], "truck failure") do
  open_ids = Alert.joins(:alert_rule).where(alert_rules: { name: "Incident: Truck Failure" }, status: Alert::ACTIVE_STATUSES).pluck(:record_id)
  vehicle = Vehicle.fleet_monitoring_poc.where.not(id: open_ids)
                   .joins(trips: :waybills).merge(Trip.status_in_transit).distinct.order(:number).first
  if vehicle.nil?
    puts "  ✗ no in-transit POC vehicle with waybills available"
    nil
  else
    puts "  vehicle #{vehicle.number} (id=#{vehicle.id})"
    status, body = api(:post, "/api/v1/incidents/vehicle.failure",
                       { entity_id: vehicle.id, payload: { failure_type: "Engine overheating", estimated_repair_minutes: 90, reported_by: "driver" } })
    check("POST /api/v1/incidents/vehicle.failure", status == 201, "HTTP #{status}")
    body&.dig("alerts", 0, "id")
  end
end

section "Incident C - Extra Vehicle Request"
extra_alert = existing_or_publish(DEMO_REFS[:extra], "extra vehicle request") do
  hub = Hub.joins(:vehicles).merge(Vehicle.fleet_monitoring_poc).distinct.order(:code).first
  if hub.nil?
    puts "  ✗ no hub with POC vehicles available"
    nil
  else
    puts "  hub #{hub.code} #{hub.name} (id=#{hub.id})"
    status, body = api(:post, "/api/v1/incidents/hub.extra_vehicle_request",
                       { entity_id: hub.id, payload: { requested_vehicle_count: 2, reason: "Inbound surge (demo)", needed_by: 4.hours.from_now.iso8601 } })
    check("POST /api/v1/incidents/hub.extra_vehicle_request", status == 201, "HTTP #{status}")
    body&.dig("alerts", 0, "id")
  end
end

incidents = { "Route Diversion" => [ diversion_alert, user_a ],
              "Truck Failure" => [ failure_alert, user_b ],
              "Extra Vehicle Request" => [ extra_alert, user_a ] }.reject { |_, (alert, _)| alert.nil? }

abort("\nNo demo incidents available - cannot continue.") if incidents.empty?

# --------------------------------------------------------- notifications
def notifications_for(alert_id, user_id)
  Notification.where(alert_id: alert_id, recipient_user_id: user_id).order(:id)
end

def report_channels(alert_id, user, label)
  rows = notifications_for(alert_id, user[:id])
  in_app = rows.select { |n| n.channel == "in_app" }
  slack = rows.select { |n| n.channel == "slack" }
  check("#{label}: in-app notification", in_app.any?, in_app.last&.message&.truncate(70))
  check("#{label}: slack notification", slack.any?, slack.any? ? "status=#{slack.last.status}#{slack.last.error_message ? " (#{slack.last.error_message})" : ''}" : "none")
  { in_app: in_app, slack: slack }
end

# ------------------------------------------------------------- lifecycle
section "Assignment"
incidents.each do |label, (alert, assignee)|
  status, body = api(:post, "/api/v1/alerts/#{alert.id}/assign", { assignee_type: "user", assignee_id: assignee[:id] })
  ok = status == 200 && body&.dig("assignee", "id") == assignee[:id]
  check("#{label} -> #{assignee[:username]}", ok, "status=#{body&.dig('status')} level=#{body&.dig('assignment_level')}")
end

puts "\n  waiting for delivery…"
incidents.each_value { |(alert, _)| wait_for_delivery(alert.id, timeout: 20) }

section "Assignee received both channels"
incidents.each do |label, (alert, assignee)|
  report_channels(alert.id, assignee, "#{label} -> #{assignee[:username]}")
end

section "Acknowledgement by the assignee (admin should be told)"
incidents.each do |label, (alert, assignee)|
  # Acting AS the assignee: the same endpoint, with their user id.
  headers = { "X-Superset-User-Id" => assignee[:id].to_s, "Content-Type" => "application/json", "Accept" => "application/json" }
  response = Thread.new do
    ScenarioHelpers.session.post("/api/v1/alerts/#{alert.id}/acknowledge", params: nil, headers: headers)
    ScenarioHelpers.session.response
  end.value
  body = response.body.present? ? JSON.parse(response.body) : nil
  check("#{label}: acknowledged by #{assignee[:username]}", response.status == 200 && body["status"] == "acknowledged",
        "acknowledged_by=#{body&.dig('acknowledged_by')}")
end

puts "\n  waiting for delivery…"
incidents.each_value { |(alert, _)| wait_for_delivery(alert.id, timeout: 20) }

section "Admin notified of the acknowledgement"
incidents.each do |label, (alert, _)|
  rows = notifications_for(alert.id, admin[:id]).select { |n| n.metadata&.dig("lifecycle_action") == "acknowledged" }
  check("#{label}: admin got an acknowledgement notification", rows.any?, rows.last&.message&.truncate(70))
end

section "Reassignment (Truck Failure: User B -> User A)"
if (failure = incidents["Truck Failure"])
  alert = failure.first
  status, body = api(:post, "/api/v1/alerts/#{alert.id}/reassign", { assignee_type: "user", assignee_id: user_a[:id] })
  check("reassigned to #{user_a[:username]}", status == 200 && body&.dig("assignee", "id") == user_a[:id])
  wait_for_delivery(alert.id, timeout: 20)
  rows = notifications_for(alert.id, user_a[:id]).select { |n| n.metadata&.dig("lifecycle_action") == "reassigned" }
  check("#{user_a[:username]} told about the reassignment", rows.any?, rows.last&.message&.truncate(70))
  prev = notifications_for(alert.id, user_b[:id]).select { |n| n.metadata&.dig("lifecycle_action") == "reassigned" }
  check("#{user_b[:username]} told it left them", prev.any?, prev.last&.message&.truncate(70))
end

section "Resolution (Extra Vehicle Request, by its assignee)"
if (extra = incidents["Extra Vehicle Request"])
  alert, assignee = extra
  headers = { "X-Superset-User-Id" => assignee[:id].to_s, "Content-Type" => "application/json", "Accept" => "application/json" }
  response = Thread.new do
    ScenarioHelpers.session.post("/api/v1/alerts/#{alert.id}/resolve",
                                 params: { resolution_note: "Extra vehicle dispatched (demo)" }.to_json, headers: headers)
    ScenarioHelpers.session.response
  end.value
  body = response.body.present? ? JSON.parse(response.body) : nil
  check("resolved by #{assignee[:username]}", response.status == 200 && body["status"] == "resolved", "resolved_at=#{body&.dig('resolved_at')}")
  wait_for_delivery(alert.id, timeout: 20)
  rows = notifications_for(alert.id, admin[:id]).select { |n| n.metadata&.dig("lifecycle_action") == "resolved" }
  check("admin told who resolved it", rows.any?, rows.last&.message&.truncate(70))
end

# -------------------------------------------------------------- parity
section "In-app / Slack parity (same Alert, same core facts)"
incidents.each do |label, (alert, _)|
  rows = Notification.where(alert_id: alert.id).to_a
  in_app = rows.select { |n| n.channel == "in_app" }
  slack = rows.select { |n| n.channel == "slack" }
  same_alert = rows.map(&:alert_id).uniq == [ alert.id ]
  check("#{label}: both channels reference Alert ##{alert.id}", same_alert && in_app.any? && slack.any?,
        "in_app=#{in_app.size} slack=#{slack.size}")
  card = IncidentNotificationPresenter.new(alert.reload).as_json
  show :incident_title, card[:incident_title]
  show :severity, card[:severity]
  show :status, card[:status]
  show :assigned_to, card.dig(:assignment, :current, :name)
  show :vehicle, card[:vehicle]
  show :view_incident, card.dig(:links, :incident)
end

section "History (one Alert, no duplicates)"
incidents.each do |label, (alert, _)|
  history = Array(alert.reload.metadata&.dig("history"))
  check("#{label}: Alert ##{alert.id} keeps its own history", history.any?, history.map { |h| h["action"] }.join(" -> "))
end
# Counts ACTIVE duplicates only: once a demo incident is resolved it is
# history, and the next run correctly opens a fresh one rather than
# re-animating it - that is the intended behaviour, not a duplicate.
duplicate_refs = DEMO_REFS.values.count do |ref|
  Alert.where("alerts.metadata -> 'incident' ->> 'demo_ref' = ?", ref).where.not(status: "resolved").count > 1
end
check("no duplicate active demo incidents", duplicate_refs.zero?, "refs with >1 active alert: #{duplicate_refs}")

puts "\n" + "=" * 70
puts $scenario_failures.to_i.zero? ? "✓ DEMO COMPLETE - all checks passed" : "✗ #{$scenario_failures} check(s) failed"
puts "=" * 70
