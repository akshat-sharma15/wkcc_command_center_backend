module Api
  module V1
    # RouteDiversion: the persisted operational diversion. Creating one
    # calculates its impact (RouteDiversionImpactService) and publishes the
    # route.diversion incident through the normal EventPublisher pipeline.
    class RouteDiversionsController < BaseController
      class InvalidWaypoint < StandardError; end

      rescue_from InvalidWaypoint, IncidentPublisher::UnknownIncident do |exception|
        render json: { error: exception.message }, status: :unprocessable_content
      end

      # GET /api/v1/route-diversions?status=active|resolved|all&vehicle=&hub=&region=&from=&to=
      # (status defaults to active; see RouteDiversionQuery)
      def index
        scope = RouteDiversionQuery.new(filter_params).scope.includes(:vehicle).order(diverted_at: :desc)
        pagy, diversions = pagy(scope)
        response.headers.merge!(pagy_headers_merge(pagy))
        render json: diversions.map { |d| RouteDiversionSerializer.new(d).as_json }
      end

      # GET /api/v1/route-diversions/summary (same filters as index)
      def summary
        render json: RouteDiversionQuery.new(filter_params).summary
      end

      def show
        render json: RouteDiversionSerializer.new(RouteDiversion.find(params[:id])).as_json
      end

      # POST /api/v1/route-diversions
      # { route_diversion: { vehicle_id, trip_id?, reason, traffic_factor?,
      #   original_path?: [waypoint], diverted_path: [waypoint],
      #   original_distance_km?, diverted_distance_km?, publish?: true } }
      # A waypoint is { hub_id } | { location_id } | { name, lat, lng }.
      # original_path defaults to the trip's planned route (origin -> via -> destination).
      def create
        attrs = params.require(:route_diversion)
        vehicle = Vehicle.find(attrs.require(:vehicle_id))
        trip = attrs[:trip_id].present? ? vehicle.trips.find(attrs[:trip_id]) : current_trip!(vehicle)

        diversion = RouteDiversionCreator.create!(
          vehicle: vehicle, trip: trip, reason: attrs[:reason], traffic_factor: attrs[:traffic_factor],
          original_path: attrs[:original_path].present? ? waypoints(attrs[:original_path]) : nil,
          diverted_path: waypoints(attrs.require(:diverted_path)),
          original_distance_km: attrs[:original_distance_km].presence, diverted_distance_km: attrs[:diverted_distance_km].presence,
          publish: attrs[:publish].to_s != "false"
        )

        render json: RouteDiversionSerializer.new(diversion.reload).as_json, status: :created
      end

      # POST /api/v1/route-diversions/:id/resolve - the vehicle is back on
      # its original route. The incident Alert is resolved separately.
      def resolve
        diversion = RouteDiversion.find(params[:id])
        diversion.resolve! unless diversion.status_resolved?
        render json: RouteDiversionSerializer.new(diversion).as_json
      end

      private

      def filter_params
        filters = params.permit(:status, :vehicle, :vehicle_id, :hub, :region, :from, :to).to_h
        filters[:vehicle] ||= filters.delete(:vehicle_id)
        filters.compact
      end

      def current_trip!(vehicle)
        vehicle.trips.where(status: EtaImpactService::MOVING_TRIP_STATUSES).order(departure_at: :desc).first ||
          raise(InvalidWaypoint, "vehicle #{vehicle.number} has no in-transit trip to divert")
      end

      def waypoints(raw)
        Array(raw).map { |point| waypoint(point.respond_to?(:permit) ? point.permit(:hub_id, :location_id, :name, :lat, :lng).to_h : point.to_h) }
      end

      def waypoint(point)
        point = point.with_indifferent_access
        if point[:hub_id].present?
          hub = Hub.includes(:geo_location).find(point[:hub_id])
          EtaImpactService.hub_point(hub) || raise(InvalidWaypoint, "hub #{hub.code} has no coordinates")
        elsif point[:location_id].present?
          location = Location.find(point[:location_id])
          { location_id: location.id, name: location.city, lat: location.latitude.to_f, lng: location.longitude.to_f }
        elsif GeoDistance.point?(point)
          { name: point[:name], lat: point[:lat].to_f, lng: point[:lng].to_f }.compact
        else
          raise InvalidWaypoint, "each waypoint needs hub_id, location_id, or lat/lng"
        end
      end
    end
  end
end
