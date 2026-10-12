# Road paths for the Fleet Map's in-transit trucks ("Show route" and the
# live movement animation). A trip's route is its CURRENT route from
# EtaImpactService - origin hub -> via waypoint -> destination hub, or an
# active diversion's path - so every truck on the same route shares one
# stored path, whatever its own position.
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

    # origin -> via -> destination as [{ lat:, lng: }], or nil when the trip
    # lacks the coordinates for a route.
    # `diversion:` as for EtaImpactService (batch callers preload it).
    def self.waypoints_for(trip, diversion: :lookup)
      points = EtaImpactService.new(trip, vehicle: trip.vehicle, diversion: diversion).current_route.map { |p| p.to_h.symbolize_keys.slice(:lat, :lng) }
      points = points.select { |p| p[:lat] && p[:lng] }
      points.size >= 2 ? points : nil
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

    private_class_method :save, :failure_cache_key
  end
end
