module Api
  module V1
    class PackageSerializer
      def initialize(package)
        @package = package
      end

      def as_json(*)
        {
          id: @package.id,
          identifier: @package.identifier,
          trip_id: @package.trip_id,
          location_type: @package.location_type,
          location_id: @package.location_id,
          expected_quantity: @package.expected_quantity,
          received_quantity: @package.received_quantity,
          damaged_quantity: @package.damaged_quantity,
          short_quantity: @package.short_quantity,
          status: @package.status,
          created_at: @package.created_at,
          updated_at: @package.updated_at
        }
      end
    end
  end
end
