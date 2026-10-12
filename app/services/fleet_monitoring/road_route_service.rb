# Road paths for the Fleet Map's in-transit trucks ("Show route" and the
# live movement animation). The request is exactly the one the map used to
# send to Google from the browser - origin hub -> the truck's position (as a
# pass-through point) -> destination hub - so routes look the same as
# before. A diverted truck's route also passes through its active
# diversion's waypoint(s), so it follows the diversion. Truck positions are
# static in the database, so each truck's route is fetched once and then
# served from road_routes to every viewer.
#
#   stored and fresh  -> served from road_routes (no Google call)
#   missing or stale  -> one Google Routes API call, then stored
#   Google fails      -> the stale copy if there is one, else nil (the map
#                        then draws its direct-line fallback); the route is
#                        not retried for FAILURE_BACKOFF, so a failing API
#                        is never hammered
module FleetMonitoring
  class RoadRouteService
    FAILURE_BACKOFF = 10.minutes

    # { route_key => encoded_polyline } for the given trips' routes that are
    # already stored, plus { trip_id => route_key }. Never calls Google.
    def self.stored_for(trips)
      diversions = RouteDiversion.active.where(trip_id: trips.map(&:id)).order(diverted_at: :desc).group_by(&:trip_id)
      keys = trips.to_h { |trip| [ trip.id, waypoints_for(trip, diversion: diversions[trip.id]&.first) ] }
                  .transform_values { |points| points && RoadRoute.key_for(points) }.compact
      polylines = RoadRoute.where(route_key: keys.values.uniq).pluck(:route_key, :encoded_polyline).to_h
      { routes: polylines, trips: keys.select { |_, key| polylines.key?(key) } }
    end

    # The trip's road route as { route_key:, encoded_polyline: }, fetching it
    # from Google when it isn't stored (or is stale). nil when unavailable.
    def self.for_trip(trip)
      points = waypoints_for(trip)
      return nil unless points

      route = fetch(points)
      route && { route_key: route.route_key, encoded_polyline: route.encoded_polyline }
    end

    # Returns the RoadRoute for these waypoints, or nil.
    def self.fetch(points)
      key = RoadRoute.key_for(points)
      stored = RoadRoute.find_by(route_key: key)
      return stored if stored&.fresh?
      return stored unless GoogleRoutesClient.configured?
      return stored if Rails.cache.exist?(failure_cache_key(key))

      result = GoogleRoutesClient.new.compute_route(points)
      save(key, points, result)
    rescue GoogleRoutesClient::ApiError => e
      Rails.logger.error("[RoadRouteService] route #{key} (#{points.size} waypoints) failed: #{e.message}")
      Rails.cache.write(failure_cache_key(key), true, expires_in: FAILURE_BACKOFF)
      stored
    end

    # origin hub -> truck position -> destination hub as [{ lat:, lng: }] -
    # the same points (and the same truck position) VehiclePresenter gives the
    # map - or nil when the trip lacks the hub coordinates for a route. With
    # an active diversion, its via waypoint(s) are added, with the truck placed
    # before or after each one by how close it is to the destination.
    # `diversion:` may be passed (batch callers preload it; nil = none).
    def self.waypoints_for(trip, diversion: :lookup)
      origin = EtaImpactService.hub_point(trip.origin_hub)
      destination = EtaImpactService.hub_point(trip.destination_hub)
      return nil unless origin && destination

      vehicle = trip.vehicle
      location = vehicle.current_geo_location
      lat = location&.latitude || vehicle.last_known_latitude
      lng = location&.longitude || vehicle.last_known_longitude
      truck = lat && lng ? { lat: lat.to_f, lng: lng.to_f } : nil

      diversion = trip.route_diversions.active.order(diverted_at: :desc).first if diversion == :lookup
      vias = diversion ? diversion_vias(diversion) : []
      ahead, behind = truck ? vias.partition { |p| GeoDistance.km(p, destination) < GeoDistance.km(truck, destination) } : [ [], vias ]
      [ origin, *behind, truck, *ahead, destination ].compact.map { |p| p.slice(:lat, :lng) }
    end

    # The diverted path's waypoints between its two ends.
    def self.diversion_vias(diversion)
      Array(diversion.diverted_path)[1...-1].to_a.map { |p| p.to_h.symbolize_keys.slice(:lat, :lng).transform_values(&:to_f) }
    end

    def self.save(key, points, result)
      route = RoadRoute.find_or_initialize_by(route_key: key)
      route.update!(waypoints: points, encoded_polyline: result[:encoded_polyline],
                    distance_meters: result[:distance_meters], fetched_at: Time.current)
      route
    rescue ActiveRecord::RecordNotUnique
      # Another request stored the same route at the same moment.
      RoadRoute.find_by!(route_key: key)
    end

    def self.failure_cache_key(key)
      "road_route:failed:#{key}"
    end

    private_class_method :save, :failure_cache_key, :diversion_vias
  end
end
