# Map hub focus: the vehicles moving into (inbound) or out of (outbound)
# one hub, filtered server-side. Counts and rows both come from
# FleetMonitoring::HubVehicleFlow - the same query behind the hub hover
# counts - so the numbers always match the vehicles drawn.
module Api
  module V1
    module FleetMonitoring
      class HubVehiclesController < Api::V1::BaseController
        before_action :set_hub

        # GET /api/v1/fleet-monitoring/hubs/:code/vehicles?direction=inbound
        def index
          direction = params[:direction].presence || "all"
          unless ::FleetMonitoring::HubVehicleFlow::DIRECTIONS.include?(direction)
            return render json: { error: "direction must be one of #{::FleetMonitoring::HubVehicleFlow::DIRECTIONS.join(', ')}" }, status: :bad_request
          end

          vehicles = ::FleetMonitoring::HubVehicleFlow.rows(@hub, direction)
          render json: { hub: EtaImpactService.hub_point(@hub), direction: direction, count: vehicles.size, vehicles: vehicles }
        end

        # GET /api/v1/fleet-monitoring/hubs/:code/vehicle-summary - flow
        # counts plus projected load/capacity/availability for the hub card.
        def summary
          load = HubLoadService.new(@hub).as_json
          render json: ::FleetMonitoring::HubVehicleFlow.summary(@hub).merge(
            load: load.slice(:projected_load_kg, :capacity_kg, :projected_utilization_pct, :congestion_risk,
                             :available_vehicle_count, :available_vehicle_capacity_kg, :inventory_kg, :unavailable)
          )
        end

        private

        # Accepts a hub code (map) or numeric id (/api/v1/hubs/:hub_id/...).
        def set_hub
          key = params[:code] || params[:hub_id]
          @hub = Hub.includes(:geo_location).find_by(code: key) || Hub.includes(:geo_location).find(key)
        end
      end
    end
  end
end
