# Indore -> Ratlam corridor used by the advanced-incident specs: real
# coordinates, an in-transit trip with packages/orders/waybills, and the
# three keyed EventDefinitions.
module IncidentFixtures
  def build_corridor(departure_at: 2.hours.ago, expected_arrival_at: 2.hours.from_now)
    indore_geo = create(:location, city: "Indore", latitude: 22.7196, longitude: 75.8577)
    ratlam_geo = create(:location, city: "Ratlam", latitude: 23.3315, longitude: 75.0367)
    ujjain_geo = create(:location, city: "Ujjain", latitude: 23.1765, longitude: 75.7885)
    origin = create(:hub, name: "Indore Test Hub", geo_location: indore_geo, load_capacity_kg: 1000)
    destination = create(:hub, name: "Ratlam Test Hub", geo_location: ratlam_geo, load_capacity_kg: 500)
    driver = create(:workforce_member, name: "Test Driver", role_type: "driver", hub: origin, phone_number: "+91 90000 00000")
    vehicle = create(:vehicle, number: "TRK-SPEC-1", hub: origin, driver: driver, fuel_efficiency_kmpl: 4.0,
                               current_location_id: ujjain_geo.id, fleet_monitoring_poc: true)
    trip = create(:trip, vehicle: vehicle, origin_hub: origin, destination_hub: destination, status: "in_transit",
                         departure_at: departure_at, expected_arrival_at: expected_arrival_at)
    order = create(:order, total_weight: 100, package_count: 2, customer_reference: "CUST-9", promised_delivery_at: expected_arrival_at + 10.minutes)
    waybill = create(:waybill, trip: trip, declared_value: 50_000, expected_arrival_at: expected_arrival_at)
    2.times { |i| create(:package, identifier: "PKG-CORR-#{i}", trip: trip, order: order, waybill: waybill, status: "in_transit", location: origin) }
    waybill.recalculate_totals!
    { origin: origin, destination: destination, vehicle: vehicle, trip: trip, order: order, waybill: waybill, driver: driver, ujjain: ujjain_geo }
  end

  def incident_rule(key, **attrs)
    IncidentCatalog.ensure_event_definitions!
    create(:alert_rule, trigger_type: "event", group: nil, field: nil, operator: nil, value: nil,
                        event_definition: IncidentCatalog.event_definition(key), severity: "critical", **attrs)
  end
end

RSpec.configure { |config| config.include IncidentFixtures }
