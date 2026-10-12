# Road paths for the map's in-transit trucks, served from the road_routes
# table (see FleetMonitoring::RoadRouteService) so the browser never calls
# the Google Routes API itself.
module Api
  module V1
    module FleetMonitoring
      class RoadRoutesController < Api::V1::BaseController
        # GET /api/v1/fleet-monitoring/road-routes
        # Every stored route for the map's current trips, each polyline once:
        # { routes: { route_key => encoded_polyline }, trips: { trip_id => route_key } }.
        # Never calls Google - trips missing here are fetched one by one via #show.
        def index
          render json: ::FleetMonitoring::RoadRouteService.stored_for(current_trips.to_a)
        end

        # GET /api/v1/fleet-monitoring/trips/:trip_id/road-route
        # One trip's route, fetched from Google (once) when not stored yet.
        # { route: { route_key:, encoded_polyline: } }, or { route: null } when
        # unavailable - the map then draws its direct-line fallback.
        def show
          trip = current_trips.find_by(id: params[:trip_id])
          return render json: { error: "No in-transit map trip #{params[:trip_id]}" }, status: :not_found unless trip

          render json: { route: ::FleetMonitoring::RoadRouteService.for_trip(trip) }
        end

        private

        def current_trips
          ::FleetMonitoring::HubVehicleFlow.current_trips
            .includes(vehicle: :current_geo_location, origin_hub: :geo_location, destination_hub: :geo_location)
        end
      end
    end
  end
end
