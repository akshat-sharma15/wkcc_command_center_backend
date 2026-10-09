# READ-ONLY diagnostic: why does a truck on the map show an open incident
# that Superset then says it can't find?
#
#   bin/rails c           # then paste this whole file, on LOCAL and on the SERVER
#   -- or --
#   bin/rails runner scripts/data/diagnose_incident_mismatch.rb
#
# Run it in BOTH environments and compare the output side by side. It never
# writes anything: no update, no create, no delete, no job enqueued, and no
# secret is printed (tokens/keys are reported only as present/absent).
#
# It replays exactly what the two sides do:
#   MAP      FleetMonitoring::VehicleBatchContext#incident - the same call that
#            puts `active_incident` + a /incident/:id link on every vehicle marker
#   SUPERSET GET /api/v1/alerts/:id (Api::V1::AlertSerializer) - what the incident
#            page fetches; the page shows "Incident not found" when that fails
#
# Locals only (no constants), so it is safe to paste more than once.

# A dev-mode console echoes every SQL statement; that buried the real output. Silenced here, restored at the end.
old_logger = ActiveRecord::Base.logger
ActiveRecord::Base.logger = nil

flags = []
flag = ->(msg) { flags << msg }
section = ->(title) { puts "\n#{'=' * 78}\n#{title}\n#{'=' * 78}" }
cap = ->(rows, n = 25) { rows.first(n).each { |r| puts "  #{r}" }; puts "  ... and #{rows.size - n} more" if rows.size > n }
safe = lambda do |label, &blk|
  blk.call
rescue StandardError => e
  puts "  !! section '#{label}' raised #{e.class}: #{e.message.to_s[0, 200]}"
  flags << "diagnostic section '#{label}' itself failed (#{e.class})"
end

puts "INCIDENT MISMATCH DIAGNOSTIC  @ #{Time.current.iso8601}"

# ---------------------------------------------------------------------------
section.("1. ENVIRONMENT FINGERPRINT")
safe.("env") do
  revision = (ENV["GIT_REVISION"] || ENV["SOURCE_VERSION"] || `git rev-parse --short HEAD 2>/dev/null`.strip).presence || "unknown"
  puts "  rails_env           : #{Rails.env}"
  puts "  git revision        : #{revision}"
  puts "  db (operations)     : #{OperationsRecord.connection_db_config.database}"
  puts "  frontend_base       : #{IncidentLinks.frontend_base}"
  puts "  map_base            : #{IncidentLinks.map_base}"
  puts "  FRONTEND_BASE_URL   : #{ENV['FRONTEND_BASE_URL'].inspect}   FLEET_MAP_BASE_URL: #{ENV['FLEET_MAP_BASE_URL'].inspect}"
  puts "  CORS_ALLOWED_ORIGINS: #{ENV.fetch('CORS_ALLOWED_ORIGINS', '(unset -> *)').inspect}"
  puts "  force_ssl / assume_ssl: #{Rails.application.config.force_ssl.inspect} / #{Rails.application.config.assume_ssl.inspect}"
  puts "  SLACK channel set?  : #{ENV['SLACK_NOTIFICATION_CHANNEL'].present?}"
  slack = Integration.find_by(provider: "slack")
  puts "  slack integration   : #{slack ? "status=#{slack.status} connected=#{slack.connected?} token=#{slack.bot_token.present? ? 'present' : 'ABSENT'}" : 'none'}"
  missing = SupersetRecord::REQUIRED_ENV_VARS.reject { |k| ENV[k].present? }
  puts "  superset configured : #{SupersetDirectory.configured?}#{missing.any? ? "   MISSING ENV: #{missing.join(', ')}" : ''}"
  puts "  DB names (env)      : OPERATIONS_DB_NAME=#{ENV['OPERATIONS_DB_NAME'].inspect} (a production Puma REQUIRES this; dev falls back to wkcc_ops_development)"
  flag.("force_ssl is ON: an http:// API call from the browser gets a redirect, which a cross-origin fetch treats as a failure") if Rails.application.config.force_ssl
  flag.("CORS_ALLOWED_ORIGINS is unset ('*'); fine functionally but confirm that is intended") unless ENV["CORS_ALLOWED_ORIGINS"].present?
  flag.("map/frontend base still points at localhost: links are unusable for anyone else") if [ IncidentLinks.frontend_base, IncidentLinks.map_base ].any? { |u| u.include?("localhost") } && Rails.env.production?
  flag.("Superset is NOT configured in this process (missing env: #{missing.join(', ')}). Consequence: every alert rule resolves to zero recipients, so NEW alerts create NO notifications, and assignee names cannot be resolved") unless SupersetDirectory.configured?
end

# ---------------------------------------------------------------------------
section.("2. SUPERSET USERS (notification recipients are addressed by these ids)")
users = []
safe.("users") do
  users = SupersetDirectory.users
  users.each { |u| puts "  id=#{u[:id].to_s.ljust(4)} #{u[:username].to_s.ljust(18)} #{u[:email]}" }
  puts "  roles: #{SupersetDirectory.roles.map { |r| "#{r[:id]}:#{r[:name]}" }.join(', ')}"
end
user_ids = users.map { |u| u[:id] }

# ---------------------------------------------------------------------------
section.("3. FLEET (what the map serves)")
safe.("fleet") do
  poc = Vehicle.fleet_monitoring_poc
  in_transit = Trip.status_in_transit.select(:vehicle_id)
  puts "  vehicles total / on map (fleet_monitoring_poc): #{Vehicle.count} / #{poc.count}"
  puts "  status (all)    : #{Vehicle.group(:status).count.inspect}"
  puts "  status (on map) : #{poc.group(:status).count.inspect}"
  puts "  on map in transit: #{poc.where(id: in_transit).count}"
  puts "  waybills: #{Waybill.count}   open alerts: #{Alert.where.not(status: 'resolved').count}   notifications: #{Notification.count}"
end

# ---------------------------------------------------------------------------
section.("4. ALERT RULES + EVENT DEFINITIONS (different rules => different alerts)")
safe.("rules") do
  rules = AlertRule.order(:id).map do |r|
    resolved = begin AlertRecipientResolver.new(r).user_ids rescue [ "ERR" ] end
    "##{r.id.to_s.ljust(3)} #{r.name.to_s[0, 34].ljust(34)} #{r.trigger_type.to_s.ljust(9)} enabled=#{r.enabled.to_s.ljust(5)} notify=#{r.notify.to_s.ljust(5)} " \
      "ch=#{Array(r.notification_channels).join('+').ljust(12)} recipient=#{r.recipient_type}:#{r.recipient_id} -> users #{resolved.inspect}#{' [DELETED]' if r.deleted_at}"
  end
  cap.(rules, 40)
  puts "  event definitions: #{EventDefinition.order(:id).map { |e| e.key.presence || e.name }.inspect}"
  AlertRule.where(enabled: true, notify: true, deleted_at: nil).find_each do |r|
    next unless SupersetDirectory.configured? # already flagged once in section 1; do not repeat it per rule

    ids = begin AlertRecipientResolver.new(r).user_ids rescue [] end
    flag.("rule ##{r.id} '#{r.name}' is enabled+notify but resolves to NO recipients (nobody will be notified)") if ids.empty?
  end
end

# ---------------------------------------------------------------------------
section.("5. MAP SIDE vs SUPERSET SIDE, per vehicle that shows an incident")
shown = []
safe.("map-vs-superset") do
  vehicles = Vehicle.fleet_monitoring_poc.order(:number).to_a
  ctx = FleetMonitoring::VehicleBatchContext.new(vehicles)
  vehicles.each do |v|
    inc = ctx.incident(v.id)
    shown << [ v, inc ] if inc
  end
  puts "  vehicles on the map showing an active_incident: #{shown.size} of #{vehicles.size}"
  puts
  puts "  #{'vehicle'.ljust(12)} #{'alert'.ljust(6)} #{'status'.ljust(12)} #{'sev'.ljust(8)} #{'fetch'.ljust(7)} #{'card'.ljust(5)} #{'notif(in/sl)'.ljust(12)} #{'recipients'.ljust(14)} rule"
  rows = shown.map do |v, inc|
    alert = Alert.find_by(id: inc[:id])
    unless alert
      flag.("MAP links vehicle #{v.number} to alert ##{inc[:id]} which does NOT exist in this database")
      next "#{v.number.ljust(12)} ##{inc[:id].to_s.ljust(5)} MISSING-IN-DB"
    end

    serialized = begin
      Api::V1::AlertSerializer.new(alert).as_json
    rescue StandardError => e
      flag.("alert ##{alert.id} (#{v.number}): GET /alerts/:id would FAIL -> #{e.class}: #{e.message.to_s[0, 90]}")
      nil
    end
    card = serialized && serialized[:card].present?
    flag.("alert ##{alert.id} (#{v.number}) '#{alert.alert_rule&.name}' has NO incident card - only the 3 advanced incidents (truck failure / route diversion / extra vehicle request) get one, so the map links this vehicle to an incident page that has no incident details and no actions") if serialized && !card

    nots = Notification.where(alert_id: alert.id)
    by_channel = nots.group(:channel).count
    recips = nots.distinct.pluck(:recipient_user_id)
    flag.("alert ##{alert.id} (#{v.number}) has NO notifications at all") if nots.none?
    (recips - user_ids).each { |id| flag.("alert ##{alert.id}: notification addressed to user #{id} who does not exist in Superset here") } if users.any?
    if alert.assignee_type == "user" && users.any? && !user_ids.include?(alert.assignee_id)
      flag.("alert ##{alert.id}: assigned to user #{alert.assignee_id} who does not exist in Superset here")
    end
    link_ok = inc[:url].to_s.start_with?(IncidentLinks.frontend_base)
    flag.("alert ##{alert.id}: map link #{inc[:url]} does not start with frontend_base #{IncidentLinks.frontend_base}") unless link_ok

    "#{v.number.ljust(12)} ##{alert.id.to_s.ljust(5)} #{alert.status.ljust(12)} #{alert.severity.to_s.ljust(8)} #{(serialized ? 'ok' : 'FAIL').ljust(7)} " \
      "#{(card ? 'yes' : 'NO').ljust(5)} #{"#{by_channel['in_app'].to_i}/#{by_channel['slack'].to_i}".ljust(12)} #{recips.inspect.ljust(14)} #{alert.alert_rule&.name}"
  end
  cap.(rows, 60)
end

# ---------------------------------------------------------------------------
section.("6. ALERT / NOTIFICATION HEALTH (whole database)")
safe.("health") do
  puts "  alerts by status        : #{Alert.group(:status).count.inspect}"
  puts "  alerts by rule (open)   : #{Alert.where.not(status: 'resolved').joins(:alert_rule).group('alert_rules.name').count.inspect}"
  puts "  notifications by channel/status: #{Notification.group(:channel, :status).count.map { |(c, s), n| "#{c}/#{s}=#{n}" }.join('  ')}"
  puts "  notifications by recipient     : #{Notification.group(:recipient_user_id).count.inspect}"
  puts "  alerts with no incident snapshot: #{Alert.where("alerts.metadata -> 'incident' IS NULL").count}   with snapshot: #{Alert.where("alerts.metadata -> 'incident' IS NOT NULL").count}"

  # incidents that name a vehicle which no longer exists / is off the map
  stale = []
  Alert.where("alerts.metadata -> 'incident' -> 'vehicle' ->> 'id' IS NOT NULL").find_each do |a|
    vid = a.metadata.dig("incident", "vehicle", "id").to_i
    v = Vehicle.find_by(id: vid)
    if v.nil? then stale << "alert ##{a.id}: names vehicle id #{vid} -> MISSING"
    elsif v.number != a.metadata.dig("incident", "vehicle", "number") then stale << "alert ##{a.id}: snapshot says #{a.metadata.dig('incident', 'vehicle', 'number')} but vehicle is now #{v.number}"
    elsif !v.fleet_monitoring_poc then stale << "alert ##{a.id}: vehicle #{v.number} is not on the map (fleet_monitoring_poc=false)"
    end
  end
  puts "  incident snapshots naming a bad/stale vehicle: #{stale.size}"
  cap.(stale, 15)
  flag.("#{stale.size} incident snapshot(s) disagree with the vehicle record (see section 6)") if stale.any?

  # links stored in the database that point at the wrong place
  bad_links = 0
  [ Alert, Notification ].each do |m|
    m.where.not(metadata: nil).find_each do |r|
      Array(r.metadata.dig("incident", "links")&.values).each do |u|
        next unless u.is_a?(String)
        base = u.include?("/?") ? IncidentLinks.map_base : IncidentLinks.frontend_base
        bad_links += 1 unless u.start_with?(base)
      end
    end
  end
  puts "  stored links not matching the current bases: #{bad_links}"
  flag.("#{bad_links} stored link(s) point at a host other than the current FRONTEND_BASE_URL/FLEET_MAP_BASE_URL (run scripts/data/backfill_incident_link_hosts.rb)") if bad_links.positive?

  orphan_alerts = Alert.where(status: Alert::ACTIVE_STATUSES).where.not(alert_rule_id: AlertRule.select(:id)).count
  flag.("#{orphan_alerts} active alert(s) reference a rule that no longer exists") if orphan_alerts.positive?
  deleted_rule_alerts = Alert.where(status: Alert::ACTIVE_STATUSES, alert_rule_id: AlertRule.where.not(deleted_at: nil).select(:id)).count
  puts "  active alerts whose rule is soft-deleted: #{deleted_rule_alerts}"
end

# ---------------------------------------------------------------------------
section.("7. WHAT TO CHECK IN THE BROWSER (cannot be seen from here)")
puts "  Open the Superset incident page for an alert from section 5, DevTools -> Network,"
puts "  find the request to  /api/v1/alerts/<id>  and note:"
puts "    - the HOST it calls (Superset's COMMAND_CENTER_API_HOST is baked in at BUILD time,"
puts "      default localhost:3001 -> on a deployed Superset that is the *visitor's own machine*)"
puts "    - status: 200 = alert exists | 404 = alert not in THIS db | (blocked)/CORS = origin not allowed"
puts "      | 301/302 = force_ssl redirect | 500 = serializer error (section 5 shows 'FAIL')"

# ---------------------------------------------------------------------------
section.("SUMMARY - things that will cause 'map shows an incident, Superset can't open it'")
if flags.empty?
  puts "  (none detected in the database)"
else
  flags.uniq.each_with_index { |f, i| puts "  #{i + 1}. #{f}" }
end
ActiveRecord::Base.logger = old_logger
puts "\nDone (read-only). Run the same script on the other environment and compare."
