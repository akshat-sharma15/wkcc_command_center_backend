# Waybill shape for the fleet map's waybill search result: the document,
# where it is (vehicle, trip, route, current ETA) and any active incident
# about its vehicle - one response, no follow-up fetches needed to render.
module FleetMonitoring
  class WaybillPresenter
    def initialize(waybill)
      @waybill = waybill
    end

    def as_json(*)
      trip = @waybill.trip
      vehicle = @waybill.vehicle
      moving = trip && EtaImpactService::MOVING_TRIP_STATUSES.include?(trip.status)
      eta = moving ? EtaImpactService.new(trip, vehicle: vehicle) : nil
      incident = VehicleBatchContext.new([ vehicle ]).incident(vehicle.id)
      {
        waybill_number: @waybill.waybill_number,
        status: @waybill.status,
        vehicle_pnr: vehicle.number,
        vehicle_status: VehicleStatusResolver.resolve(vehicle, current_trip: moving ? trip : nil),
        trip_id: @waybill.trip_id,
        trip_status: trip&.status,
        origin: EtaImpactService.hub_point(@waybill.origin_hub) || { code: @waybill.origin_hub.code, name: @waybill.origin_hub.name },
        destination: EtaImpactService.hub_point(@waybill.destination_hub) || { code: @waybill.destination_hub.code, name: @waybill.destination_hub.name },
        customer: @waybill.customer_reference,
        customer_count: @waybill.customer_count,
        package_count: @waybill.total_packages,
        order_count: @waybill.total_orders,
        weight_kg: @waybill.total_weight&.to_f,
        expected_arrival_at: @waybill.expected_arrival_at&.iso8601,
        predicted_eta: eta&.predicted_eta&.iso8601,
        diverted: eta&.diversion.present? || false,
        diversion_id: eta&.diversion&.id,
        incident: incident && incident.merge(url: IncidentLinks.incident(incident[:id]))
      }
    end
  end
end
