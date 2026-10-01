module Api
  module V1
    class WaybillSerializer
      def initialize(waybill)
        @waybill = waybill
      end

      def as_json(*)
        {
          id: @waybill.id,
          waybill_number: @waybill.waybill_number,
          vehicle_id: @waybill.vehicle_id,
          vehicle_number: @waybill.vehicle&.number,
          trip_id: @waybill.trip_id,
          origin: hub(@waybill.origin_hub),
          destination: hub(@waybill.destination_hub),
          status: @waybill.status,
          customer: @waybill.customer_reference,
          customer_count: @waybill.customer_count,
          total_packages: @waybill.total_packages,
          total_weight_kg: @waybill.total_weight&.to_f,
          declared_value: @waybill.declared_value&.to_f,
          planned_departure_at: @waybill.planned_departure_at,
          expected_arrival_at: @waybill.expected_arrival_at,
          actual_arrival_at: @waybill.actual_arrival_at,
          metadata: @waybill.metadata,
          created_at: @waybill.created_at,
          updated_at: @waybill.updated_at
        }
      end

      private

      def hub(hub)
        hub && { id: hub.id, code: hub.code, name: hub.name }
      end
    end
  end
end
