# Planned vs predicted ETA for one trip - the single place ETA is derived
# (fleet presenters, RouteDiversionImpactService, AlertEnrichmentService
# and the hub load projection all call this rather than re-deriving it).
#
# Everything comes from existing data:
#   planned_speed_kmph = planned route distance / (expected_arrival_at -
#                        departure_at) - the trip's own planned pace
#   remaining_km       = vehicle's last known position -> remaining
#                        waypoints of the CURRENT route -> destination
#   predicted_eta      = now + remaining_km / planned_speed_kmph
#                        (x traffic_factor while an active diversion
#                        reports one)
# Distances are great-circle per leg (see GeoDistance). Whenever an input
# is missing the affected value is nil and `unavailable` says why - never
# a fabricated figure.
class EtaImpactService
  MOVING_TRIP_STATUSES = %w[in_transit delayed].freeze

  attr_reader :trip, :vehicle, :diversion

  # `diversion:` may be passed explicitly (batch callers preload it);
  # otherwise the trip's active RouteDiversion is looked up.
  def initialize(trip, vehicle: nil, diversion: :lookup, now: Time.current)
    @trip = trip
    @vehicle = vehicle || trip.vehicle
    @diversion = diversion == :lookup ? trip.route_diversions.active.order(diverted_at: :desc).first : diversion
    @now = now
  end

  # origin hub -> the trip's "via" waypoint (from route_info, when it
  # names a known Location) -> destination hub; an active diversion's
  # recorded original path takes precedence.
  def planned_route
    @planned_route ||= diversion&.original_path.presence ||
      [ self.class.hub_point(trip.origin_hub), self.class.via_point(trip), self.class.hub_point(trip.destination_hub) ].compact
  end

  def current_route
    @current_route ||= diversion&.diverted_path.presence || planned_route
  end

  def planned_eta
    trip.expected_arrival_at
  end

  def planned_speed_kmph
    return @planned_speed_kmph if defined?(@planned_speed_kmph)

    hours = trip.departure_at && trip.expected_arrival_at && (trip.expected_arrival_at - trip.departure_at) / 3600.0
    distance = planned_route.size >= 2 ? GeoDistance.path_km(planned_route) : nil
    @planned_speed_kmph = hours&.positive? && distance&.positive? ? distance / hours : nil
  end

  def remaining_km
    return @remaining_km if defined?(@remaining_km)

    position = current_position
    destination = current_route.last
    @remaining_km = if position && destination
      ahead = current_route[1...-1].select { |point| GeoDistance.km(point, destination) < GeoDistance.km(position, destination) }
      GeoDistance.path_km([ position, *ahead, destination ])
    end
  end

  def predicted_eta
    return @predicted_eta if defined?(@predicted_eta)

    @predicted_eta = unavailable_reason ? nil : @now + (remaining_km / planned_speed_kmph * traffic_factor).hours
  end

  def eta_variance_minutes
    return nil unless predicted_eta && planned_eta

    ((predicted_eta - planned_eta) / 60).round
  end

  def traffic_factor
    diversion&.traffic_factor&.to_f || 1.0
  end

  def unavailable_reason
    return "trip_not_in_transit" unless MOVING_TRIP_STATUSES.include?(trip.status)
    return "vehicle_stopped" if vehicle.status_maintenance? || vehicle.status_out_of_service?
    return "vehicle_position_unknown" unless current_position
    return "planned_schedule_incomplete" unless planned_speed_kmph

    nil
  end

  def as_json(*)
    {
      trip_id: trip.id,
      trip_status: trip.status,
      planned_route: planned_route,
      current_route: current_route,
      current_hub: self.class.hub_point(trip.origin_hub),
      next_hub: self.class.hub_point(trip.destination_hub),
      planned_eta: planned_eta&.iso8601,
      predicted_eta: predicted_eta&.iso8601,
      eta_variance_minutes: eta_variance_minutes,
      remaining_km: remaining_km&.round(1),
      planned_speed_kmph: planned_speed_kmph&.round(1),
      diverted: diversion.present?,
      diversion_id: diversion&.id,
      distance_basis: "great_circle",
      unavailable: unavailable_reason
    }
  end

  VIA_PATTERN = /\bvia\s+([A-Za-z][A-Za-z .'-]*?)\s*\z/i

  # The waypoint named in a trip's route_info ("A to B via Ujjain"), as a
  # point, or nil when none is named or the city has no Location.
  # City -> point lookups are memoized (waypoint Locations don't move).
  def self.via_point(trip)
    city = trip.route_info.to_s[VIA_PATTERN, 1]&.strip
    return nil if city.blank?

    via_cache.compute_if_absent(city.downcase) do
      # A city's reference point, never a vehicle's own position row that
      # merely carries that city as its label.
      location = via_point_location(city)
      location ? { name: location.city, lat: location.latitude.to_f, lng: location.longitude.to_f } : false
    end.presence
  end

  def self.via_point_location(city)
    Location.where("LOWER(city) = ?", city.to_s.downcase)
            .where.not(id: Vehicle.where.not(current_location_id: nil).select(:current_location_id))
            .order(:id).first
  end

  def self.via_cache
    @via_cache ||= Concurrent::Map.new
  end

  def self.hub_point(hub)
    return nil unless hub

    geo = hub.geo_location
    return nil unless geo

    { hub_id: hub.id, code: hub.code, name: hub.name, lat: geo.latitude.to_f, lng: geo.longitude.to_f }
  end

  private

  def current_position
    location = vehicle.current_geo_location
    lat = location&.latitude || vehicle.last_known_latitude
    lng = location&.longitude || vehicle.last_known_longitude
    lat && lng ? { lat: lat.to_f, lng: lng.to_f } : nil
  end
end
