module Api
  module V1
    class TripSerializer
      def initialize(trip)
        @trip = trip
      end

      def as_json(*)
        {
          id: @trip.id,
          vehicle_id: @trip.vehicle_id,
          origin_hub_id: @trip.origin_hub_id,
          destination_hub_id: @trip.destination_hub_id,
          departure_at: @trip.departure_at,
          expected_arrival_at: @trip.expected_arrival_at,
          actual_arrival_at: @trip.actual_arrival_at,
          status: @trip.status,
          route_info: @trip.route_info,
          created_at: @trip.created_at,
          updated_at: @trip.updated_at
        }
      end
    end
  end
end
