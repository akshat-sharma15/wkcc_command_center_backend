# Fixes Alert/Notification records that still show a vehicle's OLD number
# (e.g. "TRK-102" from before scripts/data/realistic_vehicle_data.rb
# renamed it to "MP09NH4567") - the vehicle's own row already has the
# current number (vehicle_id/record_id never changed), but the incident
# SNAPSHOT that AlertEnrichmentService took at alert-creation time
# (alerts.metadata->incident, and the Notification rows built from it at
# notification-creation time - see AlertNotificationMessageBuilder) is a
# point-in-time copy that a rename doesn't touch.
#
#   bin/rails runner scripts/data/backfill_stale_vehicle_numbers.rb
#
# For each alert whose snapshot's vehicle.number disagrees with the LIVE
# vehicle (resolved via the alert's own record_id -> Vehicle, or ->
# RouteDiversion -> Vehicle for route.diversion - never a blind global
# find/replace), this substitutes the exact old number for the new one
# everywhere it appears in:
#   - that alert's own metadata->incident (vehicle.number, and the free-text
#     "summary" sentence, e.g. "Truck TRK-102 has failed...")
#   - that alert's Notification rows' message and metadata columns (the
#     same free text and incident-card copy, persisted separately at
#     notification-creation time)
# Nothing else is touched: no other alerts, no other notifications, no new
# alerts created, no vehicle/trip/waybill records changed. History entries
# store ids only (never free text), so they're already correct.
#
# Idempotent: an alert whose snapshot already matches the live vehicle is
# left alone, so rerunning finds nothing left to fix.
puts "=" * 70
puts "BACKFILL STALE VEHICLE NUMBERS IN ALERT/NOTIFICATION HISTORY"
puts "=" * 70

def live_vehicle_for(alert)
  key = alert.metadata.dig("incident", "key")
  case key
  when "vehicle.failure" then Vehicle.find_by(id: alert.record_id)
  when "route.diversion" then RouteDiversion.find_by(id: alert.record_id)&.vehicle
  end
end

# Replaces every occurrence of `old_value` with `new_value` inside any
# String found while walking a Hash/Array structure - used on parsed JSON
# (Alert#metadata, Notification#metadata), never on arbitrary text.
def substitute(node, old_value, new_value)
  case node
  when Hash then node.transform_values { |v| substitute(v, old_value, new_value) }
  when Array then node.map { |v| substitute(v, old_value, new_value) }
  when String then node.gsub(old_value, new_value)
  else node
  end
end

fixed_alerts = []
skipped_no_live_vehicle = []
fixed_notifications = 0
manual_review = []

Alert.where.not(metadata: nil).find_each do |alert|
  old_number = alert.metadata.dig("incident", "vehicle", "number")
  next unless old_number # not a vehicle-bearing incident (e.g. hub.extra_vehicle_request)

  live_vehicle = live_vehicle_for(alert)
  if live_vehicle.nil?
    # The vehicle/diversion this alert pointed at no longer resolves
    # (deleted?) - can't safely determine the "current" number, so this is
    # left for manual review rather than guessed at.
    manual_review << { alert_id: alert.id, old_number: old_number, reason: "vehicle/diversion no longer resolves" }
    next
  end

  new_number = live_vehicle.number
  next if new_number == old_number # already current - idempotent no-op

  Alert.transaction do
    alert.update_columns(metadata: substitute(alert.metadata, old_number, new_number)) # rubocop:disable Rails/SkipsModelValidations

    alert.notifications.find_each do |notification|
      notification.update_columns( # rubocop:disable Rails/SkipsModelValidations
        message: notification.message&.gsub(old_number, new_number),
        metadata: notification.metadata && substitute(notification.metadata, old_number, new_number)
      )
      fixed_notifications += 1
    end
  end

  fixed_alerts << { alert_id: alert.id, old_number: old_number, new_number: new_number }
end

puts "\nAlerts fixed: #{fixed_alerts.size}"
fixed_alerts.each { |f| puts "  alert ##{f[:alert_id]}: #{f[:old_number]} -> #{f[:new_number]}" }

puts "\nNotifications fixed: #{fixed_notifications}"

if manual_review.any?
  puts "\n⚠ Needs manual review (#{manual_review.size}) - vehicle/diversion no longer exists:"
  manual_review.each { |m| puts "  alert ##{m[:alert_id]}: stale number #{m[:old_number]} (#{m[:reason]})" }
else
  puts "\n✓ No records need manual review"
end

remaining_stale = Alert.where.not(metadata: nil).find_all do |a|
  old = a.metadata.dig("incident", "vehicle", "number")
  old && (v = live_vehicle_for(a)) && v.number != old
end
puts "\nRemaining stale after this run: #{remaining_stale.size} #{remaining_stale.empty? ? '(clean)' : remaining_stale.map(&:id)}"
