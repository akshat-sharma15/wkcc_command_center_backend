# Consistency checks across the map fleet, hub flows, route diversions and
# notifications. Read-only; exits non-zero when any check fails.
#
#   bin/rails runner scripts/data/validate_operational_consistency.rb
ROUTE_TOLERANCE_KM = FleetMonitoring::VehiclePositionPlanner::MAX_SIDE_OFFSET_KM + 1.0
YARD_TOLERANCE_KM = FleetMonitoring::VehiclePositionPlanner::YARD_RADIUS_KM.max + 1.0
ETA_TOLERANCE_MINUTES = 45
INDIA = { lat: 6.0..37.5, lng: 68.0..97.5 }.freeze

$failures = Hash.new { |h, k| h[k] = [] }
def fail!(section, message) = $failures[section] << message

# Shortest distance (km) from a point to a polyline, equirectangular.
def distance_to_path_km(point, path)
  project = ->(p) { [ GeoDistance.fetch(p, :lng).to_f * 111.0 * Math.cos(point[:lat] * Math::PI / 180), GeoDistance.fetch(p, :lat).to_f * 111.0 ] }
  px, py = project.call(point)
  path.each_cons(2).map do |from, to|
    ax, ay = project.call(from)
    bx, by = project.call(to)
    dx, dy = bx - ax, by - ay
    t = (dx.zero? && dy.zero?) ? 0 : (((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy)).clamp(0, 1)
    Math.hypot(px - (ax + t * dx), py - (ay + t * dy))
  end.min
end

puts "=" * 70
puts "OPERATIONAL CONSISTENCY VALIDATION"
puts "=" * 70

# --- Vehicles --------------------------------------------------------------
vehicles = Vehicle.fleet_monitoring_poc.includes(:current_geo_location, hub: :geo_location).to_a
trips = FleetMonitoring::HubVehicleFlow.current_trips.includes(origin_hub: :geo_location, destination_hub: :geo_location).index_by(&:vehicle_id)
diversions = RouteDiversion.active.where(trip_id: trips.values.map(&:id)).index_by(&:trip_id)
flow_rows = Hub.all.index_with { |hub| %w[inbound outbound].index_with { |d| FleetMonitoring::HubVehicleFlow.rows(hub, d).map { |r| r[:pnr] }.to_set } }
hubs_by_id = Hub.all.index_by(&:id)

vehicles.each do |vehicle|
  location = vehicle.current_geo_location
  next fail!(:vehicles, "#{vehicle.number}: no location") unless location

  point = { lat: location.latitude.to_f, lng: location.longitude.to_f }
  fail!(:vehicles, "#{vehicle.number}: coordinates outside India #{point}") unless INDIA[:lat].cover?(point[:lat]) && INDIA[:lng].cover?(point[:lng])
  trip = trips[vehicle.id]

  if trip
    diversion = diversions[trip.id]
    eta = EtaImpactService.new(trip, vehicle: vehicle, diversion: diversion)
    fail!(:vehicles, "#{vehicle.number}: in transit but status #{vehicle.status}") unless vehicle.status_active?
    off = distance_to_path_km(point, eta.current_route)
    fail!(:vehicles, "#{vehicle.number}: #{off.round(1)} km off its route #{eta.current_route.map { |p| p[:name] || p['name'] }.join(' → ')}") if off > ROUTE_TOLERANCE_KM
    fail!(:vehicles, "#{vehicle.number}: trip ##{trip.id} origin == destination") if trip.origin_hub_id == trip.destination_hub_id
    fail!(:vehicles, "#{vehicle.number}: trip ##{trip.id} arrival not after departure") unless trip.departure_at && trip.expected_arrival_at && trip.expected_arrival_at > trip.departure_at
    reference = diversion&.revised_eta || trip.expected_arrival_at
    if eta.predicted_eta.nil?
      fail!(:vehicles, "#{vehicle.number}: ETA unavailable (#{eta.unavailable_reason})")
    elsif (eta.predicted_eta - reference).abs > ETA_TOLERANCE_MINUTES.minutes
      fail!(:vehicles, "#{vehicle.number}: predicted ETA #{eta.predicted_eta.strftime('%d %H:%M')} vs planned #{reference.strftime('%d %H:%M')} (> #{ETA_TOLERANCE_MINUTES} min apart)")
    end
    fail!(:vehicles, "#{vehicle.number}: missing from #{hubs_by_id[trip.destination_hub_id].code} inbound") unless flow_rows[hubs_by_id[trip.destination_hub_id]]["inbound"].include?(vehicle.number)
    fail!(:vehicles, "#{vehicle.number}: missing from #{hubs_by_id[trip.origin_hub_id].code} outbound") unless flow_rows[hubs_by_id[trip.origin_hub_id]]["outbound"].include?(vehicle.number)
  else
    home = EtaImpactService.hub_point(vehicle.hub)
    next fail!(:vehicles, "#{vehicle.number}: home hub has no coordinates") unless home

    distance = GeoDistance.km(point, home)
    fail!(:vehicles, "#{vehicle.number}: not on a trip but #{distance.round(1)} km from home hub #{vehicle.hub.code}") if distance > YARD_TOLERANCE_KM
  end
end
in_flows = flow_rows.values.sum { |d| d["inbound"].size }
puts "\n[Vehicles] #{vehicles.size} map vehicles · #{trips.size} in transit · #{vehicles.size - trips.size} at hubs · #{$failures[:vehicles].size} problem(s)"
puts "  numbers unique: #{Vehicle.group(:number).having('COUNT(*) > 1').count.empty?} · inbound flow rows #{in_flows} == in-transit #{trips.size}: #{in_flows == trips.size}"
fail!(:vehicles, "inbound flow rows (#{in_flows}) != in-transit vehicles (#{trips.size})") unless in_flows == trips.size

# --- Hubs ------------------------------------------------------------------
counts = FleetMonitoring::HubVehicleFlow.counts_by_hub
Hub.includes(:geo_location).find_each do |hub|
  summary = FleetMonitoring::HubVehicleFlow.summary(hub)
  presented = FleetMonitoring::HubPresenter.new(hub, flow_counts: counts.fetch(hub.id, { inbound: 0, outbound: 0 })).as_json
  %w[inbound outbound].each do |direction|
    listed = flow_rows[hub][direction].size
    fail!(:hubs, "#{hub.code} #{direction}: summary #{summary[:"#{direction}_count"]} != list #{listed}") unless summary[:"#{direction}_count"] == listed
    fail!(:hubs, "#{hub.code} #{direction}: hover #{presented[direction.to_sym]} != list #{listed}") unless presented[direction.to_sym] == listed
  end
end
puts "\n[Hubs] #{Hub.count} hubs · hover count == summary count == map list for inbound and outbound · #{$failures[:hubs].size} problem(s)"

# --- Route diversions -------------------------------------------------------
RouteDiversion.includes(:trip, :vehicle).find_each do |d|
  label = "diversion ##{d.id} (#{d.vehicle.number}, #{d.status})"
  fail!(:diversions, "#{label}: vehicle is not the trip's vehicle") unless d.trip.vehicle_id == d.vehicle_id
  fail!(:diversions, "#{label}: original route missing") unless d.original_path.size >= 2
  fail!(:diversions, "#{label}: diverted route missing") unless d.diverted_path.size >= 2
  next unless d.status_active?

  fail!(:diversions, "#{label}: additional distance #{d.additional_distance_km} < 0") if d.additional_distance_km.to_f.negative?
  fail!(:diversions, "#{label}: revised ETA before original ETA") if d.revised_eta && d.original_eta && d.revised_eta < d.original_eta
  open_waybills = d.trip.waybills.open.count
  fail!(:diversions, "#{label}: affected waybills #{d.affected_waybills} but trip has #{open_waybills} open waybills") unless d.affected_waybills == open_waybills
  fail!(:diversions, "#{label}: incident alert missing") unless d.alert
end
summary = RouteDiversionQuery.new.summary
puts "\n[Route diversions] #{RouteDiversion.count} total · active: #{summary.except(:filters)} · #{$failures[:diversions].size} problem(s)"

# --- Notifications ----------------------------------------------------------
known_users = SupersetDirectory.configured? ? SupersetDirectory.users.map { |u| u[:id] }.to_set : nil
Notification.includes(:alert).find_each do |n|
  fail!(:notifications, "notification ##{n.id}: alert missing") unless n.alert
  fail!(:notifications, "notification ##{n.id}: unsupported channel #{n.channel}") unless Notification::CHANNELS.include?(n.channel)
  fail!(:notifications, "notification ##{n.id}: recipient #{n.recipient_user_id} not a Superset user") if known_users && !known_users.include?(n.recipient_user_id)
  fail!(:notifications, "notification ##{n.id}: delivered to Slack without a message ts") if n.channel == "slack" && n.status == "delivered" && n.external_reference.blank?
end
# In-app and Slack are two deliveries of ONE alert: same alert, same title.
pairs = Notification.where(alert_id: Alert.where("metadata ? 'incident'").select(:id)).group_by { |n| [ n.alert_id, n.recipient_user_id ] }
pairs.each_value do |group|
  titles = group.map(&:title).uniq
  fail!(:notifications, "alert ##{group.first.alert_id}: in-app/Slack titles differ #{titles}") if titles.size > 1
end
puts "\n[Notifications] #{Notification.count} notifications · #{pairs.size} incident deliveries checked for in-app/Slack parity · #{$failures[:notifications].size} problem(s)"

total = $failures.values.sum(&:size)
$failures.each do |section, messages|
  next if messages.empty?

  puts "\n✗ #{section}:"
  messages.first(15).each { |m| puts "    - #{m}" }
  puts "    … #{messages.size - 15} more" if messages.size > 15
end
puts "\n#{total.zero? ? '✓ ALL CONSISTENCY CHECKS PASSED' : "✗ #{total} problem(s)"}"
$stdout.flush
exit!(total.zero? ? 0 : 1)
