module Api
  module V1
    class HubSerializer
      def initialize(hub)
        @hub = hub
      end

      def as_json(*)
        {
          id: @hub.id,
          name: @hub.name,
          code: @hub.code,
          location: @hub.location,
          capacity: @hub.capacity,
          parking_capacity: @hub.parking_capacity,
          available_parking: @hub.available_parking,
          operational_status: @hub.operational_status,
          created_at: @hub.created_at,
          updated_at: @hub.updated_at
        }
      end
    end
  end
end
