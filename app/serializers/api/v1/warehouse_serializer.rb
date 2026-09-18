module Api
  module V1
    class WarehouseSerializer
      def initialize(warehouse)
        @warehouse = warehouse
      end

      def as_json(*)
        {
          id: @warehouse.id,
          name: @warehouse.name,
          code: @warehouse.code,
          location: @warehouse.location,
          capacity: @warehouse.capacity,
          status: @warehouse.status,
          created_at: @warehouse.created_at,
          updated_at: @warehouse.updated_at
        }
      end
    end
  end
end
