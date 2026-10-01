# Every waybill on the map fleet's current trips, in one compact batch -
# loaded by the map alongside vehicles/hubs/packages at startup so a
# truck's waybills render immediately (no per-truck fetch). Three queries
# regardless of fleet size.
module Api
  module V1
    module FleetMonitoring
      class WaybillsController < Api::V1::BaseController
        # GET /api/v1/fleet-monitoring/waybills
        def index
          trips = ::FleetMonitoring::HubVehicleFlow.current_trips
          waybills = Waybill.where(trip_id: trips.select(:id)).includes(:vehicle, :destination_hub).order(:waybill_number).to_a
          customers = Package.joins(:order).where(waybill_id: waybills.map(&:id))
                             .distinct.pluck(:waybill_id, "orders.customer_reference")
                             .group_by(&:first).transform_values { |rows| rows.filter_map(&:last) }

          render json: waybills.map { |waybill|
            refs = customers.fetch(waybill.id, [])
            {
              waybill_number: waybill.waybill_number,
              pnr: waybill.vehicle.number,
              trip_id: waybill.trip_id,
              status: waybill.status,
              customer: refs.one? ? refs.first : nil,
              customer_count: waybill.customer_count,
              total_packages: waybill.total_packages,
              destination: { code: waybill.destination_hub.code, name: waybill.destination_hub.name },
              expected_arrival_at: waybill.expected_arrival_at&.iso8601
            }
          }
        end
      end
    end
  end
end
