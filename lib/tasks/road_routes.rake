# Fills the road_routes table for every in-transit map trip, so the map's
# routes and truck movement come from the database instead of the Google
# Routes API. Calls Google only for routes not stored yet (or stale) - about
# one per in-transit truck the first time, then none until positions change
# or routes age out. Safe to re-run.
#
#   bin/rails fleet_monitoring:road_routes:prefetch
namespace :fleet_monitoring do
  namespace :road_routes do
    desc "Store the road route of every in-transit Fleet Map trip (Google Routes API only for missing ones)"
    task prefetch: :environment do
      abort "GOOGLE_ROUTES_API_KEY is not set" unless GoogleRoutesClient.configured?

      trips = FleetMonitoring::HubVehicleFlow.current_trips
                .includes(vehicle: :current_geo_location, origin_hub: :geo_location, destination_hub: :geo_location).to_a
      routes = trips.filter_map { |trip| FleetMonitoring::RoadRouteService.waypoints_for(trip) }.uniq { |p| RoadRoute.key_for(p) }
      already = RoadRoute.fresh.where(route_key: routes.map { |p| RoadRoute.key_for(p) }).count
      puts "#{trips.size} in-transit trips, #{routes.size} distinct routes, #{already} already stored."

      fetched = failed = 0
      routes.each do |points|
        key = RoadRoute.key_for(points)
        next if RoadRoute.fresh.exists?(route_key: key)

        FleetMonitoring::RoadRouteService.fetch(points)&.fresh? ? fetched += 1 : failed += 1
      end
      puts "Fetched #{fetched} from Google, #{failed} failed (see log). Stored now: #{RoadRoute.fresh.where(route_key: routes.map { |p| RoadRoute.key_for(p) }).count}/#{routes.size}."
    end
  end
end
