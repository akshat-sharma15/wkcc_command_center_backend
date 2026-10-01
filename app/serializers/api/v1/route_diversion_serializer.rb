module Api
  module V1
    class RouteDiversionSerializer
      def initialize(diversion)
        @diversion = diversion
      end

      def as_json(*)
        {
          id: @diversion.id,
          vehicle_id: @diversion.vehicle_id,
          vehicle_number: @diversion.vehicle&.number,
          trip_id: @diversion.trip_id,
          alert_id: @diversion.alert_id,
          status: @diversion.status,
          reason: @diversion.reason,
          diverted_at: @diversion.diverted_at,
          resolved_at: @diversion.resolved_at,
          original_path: @diversion.original_path,
          diverted_path: @diversion.diverted_path,
          original_distance_km: @diversion.original_distance_km&.to_f,
          diverted_distance_km: @diversion.diverted_distance_km&.to_f,
          additional_distance_km: @diversion.additional_distance_km&.to_f,
          original_eta: @diversion.original_eta,
          revised_eta: @diversion.revised_eta,
          delay_minutes: @diversion.delay_minutes,
          traffic_factor: @diversion.traffic_factor&.to_f,
          fuel_impact_litres: @diversion.fuel_impact_litres&.to_f,
          affected_waybills: @diversion.affected_waybills,
          affected_packages: @diversion.affected_packages,
          affected_orders: @diversion.affected_orders,
          revenue_risk: @diversion.revenue_risk&.to_f,
          impact: @diversion.impact_snapshot,
          created_at: @diversion.created_at,
          updated_at: @diversion.updated_at
        }
      end
    end
  end
end
