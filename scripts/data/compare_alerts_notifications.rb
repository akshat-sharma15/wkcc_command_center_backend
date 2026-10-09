# READ-ONLY id-level fingerprint of alerts + notifications, to compare two
# environments row by row (counts alone only say "142 vs 96", not WHICH rows).
#
#   bin/rails c      # paste this whole file, on LOCAL and on the SERVER
#   -- or --
#   bin/rails runner scripts/data/compare_alerts_notifications.rb
#
# Paste both outputs back and the differences can be computed exactly.
# Writes nothing, enqueues nothing, prints no secrets.
#
# Why ids alone are not enough: alert and notification ids come from each
# database's OWN sequence. After two copies of the data diverge, "alert 71" on
# one can be a different incident from "alert 71" on the other (that is
# exactly what a link like /incident/71 or /notification/116 trips over).
# So each alert also gets a SIGNATURE built from what it is ABOUT (rule +
# vehicle/hub + incident type + trigger date), which is comparable across
# environments even when the ids are not.

old_logger = ActiveRecord::Base.logger
ActiveRecord::Base.logger = nil
conn = OperationsRecord.connection

puts "COMPARE  env=#{Rails.env}  db=#{conn.current_database}  at=#{Time.current.iso8601}"
puts "alerts=#{Alert.count} (id #{Alert.minimum(:id)}..#{Alert.maximum(:id)})  notifications=#{Notification.count} (id #{Notification.minimum(:id)}..#{Notification.maximum(:id)})"
puts "next ids: alerts=#{conn.select_value('SELECT last_value FROM alerts_id_seq')} notifications=#{conn.select_value('SELECT last_value FROM notifications_id_seq')}"
puts "alert_rules=#{AlertRule.count} (id #{AlertRule.minimum(:id)}..#{AlertRule.maximum(:id)})  event_definitions=#{EventDefinition.count}"

# What the alert is ABOUT, independent of its id.
sig = lambda do |a|
  inc = a.metadata&.dig("incident") || {}
  about = inc.dig("vehicle", "number") || inc["hub"] || a.record_id
  [ a.alert_rule_id, a.group, about, inc["incident_type"] || a.field, a.triggered_at&.utc&.strftime("%m%dT%H%M") ].join("/")
end

puts "\n--- ALERTS: id | status | sev | signature(rule/group/about/type/triggered) | notifs(in_app,slack) ---"
by_alert = Notification.group(:alert_id, :channel).count
Alert.order(:id).each do |a|
  n_in = by_alert[[ a.id, "in_app" ]].to_i
  n_sl = by_alert[[ a.id, "slack" ]].to_i
  puts "A|#{a.id}|#{a.status}|#{a.severity}|#{sig.call(a)}|#{n_in},#{n_sl}"
end

puts "\n--- NOTIFICATIONS: id | alert_id | user | channel | status | lifecycle | created ---"
Notification.order(:id).each do |n|
  puts "N|#{n.id}|#{n.alert_id}|#{n.recipient_user_id}|#{n.channel}|#{n.status}|#{n.metadata&.dig('lifecycle_action') || '-'}|#{n.created_at.utc.strftime('%m%dT%H%M')}"
end

puts "\n--- DIGESTS (equal digests = identical sets) ---"
puts "alert ids       : #{Digest::MD5.hexdigest(Alert.order(:id).pluck(:id).join(','))}"
puts "notification ids: #{Digest::MD5.hexdigest(Notification.order(:id).pluck(:id).join(','))}"
puts "alert signatures: #{Digest::MD5.hexdigest(Alert.order(:id).map { |a| sig.call(a) }.sort.join('|'))}"

ActiveRecord::Base.logger = old_logger
puts "\nDone (read-only)."
