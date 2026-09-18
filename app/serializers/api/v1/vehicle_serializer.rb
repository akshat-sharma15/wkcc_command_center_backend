module Api
  module V1
    class VehicleSerializer
      def initialize(vehicle)
        @vehicle = vehicle
      end

      def as_json(*)
        {
          id: @vehicle.id,
          number: @vehicle.number,
          vehicle_type: @vehicle.vehicle_type,
          status: @vehicle.status,
          capacity: @vehicle.capacity,
          vendor: @vehicle.vendor,
          current_location: @vehicle.current_location,
          hub_id: @vehicle.hub_id,
          driver_id: @vehicle.driver_id,
          created_at: @vehicle.created_at,
          updated_at: @vehicle.updated_at
        }
      end
    end
  end
end
