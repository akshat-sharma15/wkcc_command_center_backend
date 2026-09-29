# In-app / Slack parity, assignment workflow, live updates and drill-through.
#   bin/rails runner scripts/alerts/11_test_notification_parity.rb
#
# A. Publishes a Truck Failure and checks the in-app notification (API) and
#    the Slack message render the SAME incident card rows and actions.
# B. acknowledge -> assign -> reassign -> escalate -> resolve through the
#    API; after each step the in-app card, the SSE "incident_update" event
#    and the re-rendered Slack message all show the same Alert status.
# G. Drill-through: incident page link, map links (truck/route/hub with
#    incident context) and the map's incident endpoint.
require_relative "support/scenario_helpers"
include ScenarioHelpers

puts "=" * 70
puts "NOTIFICATION PARITY · ASSIGNMENT · DRILL-THROUGH"
puts "=" * 70

rule = AlertRule.active.find_by(name: "Incident: Truck Failure")
abort("Run scripts/data/seed_advanced_incidents.rb first") unless rule
busy = Alert.where(alert_rule: rule).where(status: Alert::ACTIVE_STATUSES).pluck(:record_id)
vehicle = Vehicle.where("number LIKE 'TRK-%'").where.not(id: busy).where.not(id: RouteDiversion.active.select(:vehicle_id))
                 .where(id: FleetMonitoring::HubVehicleFlow.current_trips.where(id: Waybill.open.select(:trip_id)).select(:vehicle_id))
                 .order(:number).first
abort("No free in-transit TRK vehicle with waybills") unless vehicle

# Listen on the user's SSE channel (the same Redis channel the stream uses).
events = Queue.new
listener = Thread.new do
  Redis.new(url: RealtimeNotificationPublisher.redis_url).subscribe(RealtimeNotificationPublisher.channel_for(USER_ID)) do |on|
    on.message { |_channel, payload| events << JSON.parse(payload) }
  end
end
sleep 0.5

section "A. Trigger + parity"
status, body = api(:post, "/api/v1/incidents/vehicle.failure", { entity_id: vehicle.id, payload: { failure_type: "Gearbox failure", estimated_repair_minutes: 60 } })
check("POST /api/v1/incidents/vehicle.failure (#{vehicle.number})", status == 201)
alert_id = body.dig("alerts", 0, "id")
abort("  ✗ no alert") unless alert_id
report_delivery(alert_id)

_, notifications = api(:get, "/api/v1/notifications")
in_app = notifications.find { |n| n["alert_id"] == alert_id && n["channel"] == "in_app" }
slack = Notification.find_by(alert_id: alert_id, channel: "slack")
card = in_app&.fetch("incident", nil)
check("in-app notification carries the incident card", card.present?, card && "#{card['vehicle']} · #{card['route']} · #{card['waybill_count']} waybills · #{inr(card['revenue_risk'])}")
blocks = SlackIncidentMessageBuilder.new(slack).blocks
slack_rows = blocks.select { |b| b[:fields] }.flat_map { |b| b[:fields].map { |f| f[:text] } }
in_app_rows = card["fields"].reject { |f| f["label"] == "Status" }.map { |f| "*#{f['label']}:*\n#{f['value']}" }
check("Slack rows == in-app rows (#{in_app_rows.size} rows)", slack_rows == in_app_rows)
%w[vehicle driver route current_hub destination waybill_count order_count package_count predicted_eta delay_minutes revenue_risk].each do |key|
  check("  card has #{key}", !card[key].nil?, card[key].to_s)
end
check("card has primary/secondary/current assignee", %w[primary secondary current].all? { |k| card.dig("assignment", k, "name") },
      %w[primary secondary current].map { |k| "#{k}=#{card.dig('assignment', k, 'name')}" }.join(" "))
check("Slack channel id recorded for later updates", slack.reload.metadata["slack_channel"].present?)
slack_buttons = blocks.last[:elements].map { |e| e[:text][:text] }
check("Slack buttons", (%w[View\ Incident View\ Truck View\ Route View\ Hub Acknowledge Resolve] - slack_buttons).empty?, slack_buttons.join(", "))
check("in-app actions", (%w[view_incident view_truck view_route view_hub view_waybills acknowledge escalate resolve] - card["actions"]).empty?, card["actions"].join(", "))

section "B. Assignment + lifecycle (in-app, SSE, Slack in step)"
users = SupersetDirectory.users
other_user = users.find { |u| u[:id] != USER_ID } || users.first
steps = [
  [ :acknowledge, {}, "acknowledged" ],
  [ :assign, { assignee_type: "user", assignee_id: USER_ID }, "in_progress" ],
  [ :reassign, { assignee_type: "user", assignee_id: other_user[:id] }, "in_progress" ],
  [ :escalate, {}, "escalated" ],
  [ :resolve, { resolution_note: "Replacement truck assigned and shipment transferred." }, "resolved" ]
]
steps.each do |action, params, expected|
  events.clear
  status, body = api(:post, "/api/v1/alerts/#{alert_id}/#{action}", params)
  event = begin
    Timeout.timeout(5) { loop { e = events.pop; break e if e["event"] == "incident_update" && e["alert_id"] == alert_id } }
  rescue Timeout::Error
    nil
  end
  _, fresh = api(:get, "/api/v1/notifications/#{in_app['id']}")
  slack_status = SlackIncidentMessageBuilder.new(slack.reload).blocks.find { |b| b[:type] == "context" }[:elements].first[:text]
  check("#{action} -> #{expected.upcase}", status == 200 && body["status"] == expected,
        "current=#{body.dig('card', 'assignment', 'current', 'name')}")
  check("  in-app card shows #{expected.upcase}", fresh.dig("incident", "status") == expected)
  check("  SSE incident_update received", event && event.dig("incident", "status") == expected)
  check("  Slack message renders #{expected.upcase}", slack_status.include?(expected.upcase.tr("_", " ")), slack_status)
end
results = SlackIncidentSyncJob.new.perform(alert_id)
check("Slack message updated in place (chat.update)", results.any? && results.all? { |r| r[:ok] }, results.inspect)
_, final = api(:get, "/api/v1/alerts/#{alert_id}")
check("history kept (who/whom/when)", final["history"].map { |h| h["action"] } == %w[acknowledged reassigned reassigned escalated resolved],
      final["history"].map { |h| "#{h['action']}#{h['to_name'] ? "→#{h['to_name']}" : ''}" }.join(", "))
check("primary/secondary preserved", final.dig("card", "assignment", "primary", "name").present? && final.dig("card", "assignment", "secondary", "name").present?)

section "G. Drill-through"
links = final.dig("card", "links")
check("incident page link", links["incident"].end_with?("/incident/#{alert_id}"), links["incident"])
check("map truck link with incident context", links["vehicle"].include?("vehicle=#{vehicle.number}") && links["vehicle"].include?("incident=#{alert_id}"), links["vehicle"])
check("map route link", links["route"].include?("route=1"), links["route"])
check("map hub link", links["hub"].include?("hub="), links["hub"])
check("waybills link", links["waybills"].to_s.include?("section=waybills"))
status, map_card = api(:get, "/api/v1/fleet-monitoring/incidents/#{alert_id}")
check("map incident endpoint", status == 200 && map_card["vehicle"] == vehicle.number, map_card&.slice("incident_title", "status")&.to_s)
listener.kill
finish!
