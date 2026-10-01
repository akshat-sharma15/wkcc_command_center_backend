# Map overlay for one diversion: the original and diverted waypoint paths
# plus the headline impact. Fetched only when a diverted vehicle/incident
# is selected - the map never loads diversion geometry for the whole fleet.
module Api
  module V1
    module FleetMonitoring
      class RouteDiversionsController < Api::V1::BaseController
        # GET /api/v1/fleet-monitoring/route-diversions - the map's
        # "Diverted routes" layer: summary + the (active by default)
        # diversions with their paths, via RouteDiversionQuery.
        def index
          query = RouteDiversionQuery.new(params.permit(:status, :vehicle, :hub, :region, :from, :to).to_h)
          diversions = query.scope.includes(:vehicle, trip: %i[origin_hub destination_hub]).order(diverted_at: :desc).to_a
          render json: { summary: query.summary, diversions: diversions.map { |d| overlay(d) } }
        end

        def show
          render json: overlay(RouteDiversion.includes(:vehicle, trip: %i[origin_hub destination_hub]).find(params[:id]))
        end

        private

        def overlay(diversion)
          {
            id: diversion.id,
            pnr: diversion.vehicle.number,
            status: diversion.status,
            reason: diversion.reason,
            original_path: diversion.original_path,
            diverted_path: diversion.diverted_path,
            additional_distance_km: diversion.additional_distance_km&.to_f,
            delay_minutes: diversion.delay_minutes,
            original_eta: diversion.original_eta&.iso8601,
            revised_eta: diversion.revised_eta&.iso8601,
            affected_waybills: diversion.affected_waybills,
            affected_orders: diversion.affected_orders,
            revenue_risk: diversion.revenue_risk&.to_f,
            alert_id: diversion.alert_id,
            diverted_at: diversion.diverted_at&.iso8601,
            affected_packages: diversion.affected_packages,
            origin_hub: { code: diversion.trip.origin_hub.code, name: diversion.trip.origin_hub.name },
            destination_hub: { code: diversion.trip.destination_hub.code, name: diversion.trip.destination_hub.name },
            incident_url: diversion.alert_id && IncidentLinks.incident(diversion.alert_id)
          }
        end
      end
    end
  end
end
