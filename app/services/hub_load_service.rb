# Time-aware projected load for a hub, from existing operational records:
#
#   projected_load_kg = current inventory
#                     + inbound load arriving before `cutoff`
#                     - outbound load departing before `cutoff`
#
#   current inventory = packages located at the hub (pending/received)
#   inbound           = the hub's inbound map vehicles (HubVehicleFlow -
#                       the same set the map and hub counts show) whose
#                       predicted arrival (EtaImpactService; planned ETA
#                       when no prediction is possible) is at or before cutoff
#   outbound          = scheduled trips of map vehicles from the hub
#                       departing at or before cutoff (overdue included)
#
# A package's weight is its order's total_weight apportioned across the
# order's package_count (orders carry weight, packages don't). Utilisation
# needs Hub#load_capacity_kg; for a hub without one it is nil with
# `unavailable: "hub_capacity_not_configured"`.
class HubLoadService
  DEFAULT_HORIZON = 4.hours
  MOVING_TRIP_STATUSES = EtaImpactService::MOVING_TRIP_STATUSES
  PACKAGE_WEIGHT_SQL = "COALESCE(SUM(orders.total_weight / GREATEST(orders.package_count, 1)), 0)".freeze

  attr_reader :hub, :cutoff

  def initialize(hub, cutoff: nil, now: Time.current)
    @hub = hub
    @now = now
    @cutoff = cutoff || now + DEFAULT_HORIZON
  end

  def inventory_kg
    @inventory_kg ||= Package.where(location_type: "Hub", location_id: hub.id, status: %w[pending received])
                             .left_joins(:order).pick(Arel.sql(PACKAGE_WEIGHT_SQL)).to_f
  end

  def inbound_trips
    @inbound_trips ||= FleetMonitoring::HubVehicleFlow.scope(hub.id, "inbound")
                           .includes(vehicle: :current_geo_location, origin_hub: :geo_location, destination_hub: :geo_location)
                           .to_a
  end

  def outbound_moving_trips
    @outbound_moving_trips ||= FleetMonitoring::HubVehicleFlow.scope(hub.id, "outbound").to_a
  end

  def scheduled_departures
    @scheduled_departures ||= Trip.where(origin_hub_id: hub.id, status: "scheduled").where(departure_at: ..cutoff)
                                  .joins(:vehicle).merge(Vehicle.fleet_monitoring_poc).includes(:vehicle).to_a
  end

  def inbound_before_cutoff
    @inbound_before_cutoff ||= inbound_trips.filter_map do |trip|
      arrival = arrival_for(trip)
      next unless arrival && arrival <= cutoff

      { trip_id: trip.id, vehicle_id: trip.vehicle_id, vehicle_number: trip.vehicle.number,
        arrival_at: arrival.iso8601, load_kg: trip_loads.fetch(trip.id, 0.0).round(2) }
    end
  end

  def outbound_before_cutoff
    @outbound_before_cutoff ||= scheduled_departures.map do |trip|
      { trip_id: trip.id, vehicle_id: trip.vehicle_id, vehicle_number: trip.vehicle.number,
        departure_at: trip.departure_at&.iso8601, overdue: trip.departure_at.present? && trip.departure_at < @now,
        load_kg: trip_loads.fetch(trip.id, 0.0).round(2) }
    end
  end

  def projected_load_kg
    inbound = inbound_before_cutoff.sum { |row| row[:load_kg] }
    outbound = outbound_before_cutoff.sum { |row| row[:load_kg] }
    [ inventory_kg + inbound - outbound, 0 ].max.round(2)
  end

  def projected_utilization_pct
    capacity = hub.load_capacity_kg&.to_f
    capacity&.positive? ? (projected_load_kg / capacity * 100).round(1) : nil
  end

  def congestion_risk
    pct = projected_utilization_pct
    return nil unless pct
    return "high" if pct >= 90
    return "medium" if pct >= 75

    "low"
  end

  # Map vehicles homed at this hub that are serviceable and not on a trip.
  def available_vehicles
    @available_vehicles ||= Vehicle.fleet_monitoring_poc.status_active.where(hub_id: hub.id)
                                   .where.not(id: FleetMonitoring::HubVehicleFlow.current_trips.select(:vehicle_id))
                                   .to_a
  end

  def as_json(*)
    {
      hub: EtaImpactService.hub_point(hub) || { hub_id: hub.id, code: hub.code, name: hub.name },
      as_of: @now.iso8601,
      cutoff: cutoff.iso8601,
      inventory_kg: inventory_kg.round(2),
      inbound_vehicle_count: inbound_trips.size,
      outbound_vehicle_count: outbound_moving_trips.size,
      scheduled_departure_count: scheduled_departures.size,
      inbound_before_cutoff: inbound_before_cutoff,
      outbound_before_cutoff: outbound_before_cutoff,
      inbound_load_kg: inbound_before_cutoff.sum { |row| row[:load_kg] }.round(2),
      outbound_load_kg: outbound_before_cutoff.sum { |row| row[:load_kg] }.round(2),
      projected_load_kg: projected_load_kg,
      capacity_kg: hub.load_capacity_kg&.to_f,
      projected_utilization_pct: projected_utilization_pct,
      congestion_risk: congestion_risk,
      available_vehicle_count: available_vehicles.size,
      available_vehicle_capacity_kg: available_vehicles.sum { |vehicle| vehicle.capacity.to_i },
      unavailable: hub.load_capacity_kg ? nil : "hub_capacity_not_configured"
    }
  end

  private

  def arrival_for(trip)
    eta = EtaImpactService.new(trip, vehicle: trip.vehicle, diversion: active_diversions[trip.id], now: @now)
    eta.predicted_eta || trip.expected_arrival_at
  end

  def active_diversions
    @active_diversions ||= RouteDiversion.active.where(trip_id: inbound_trips.map(&:id)).index_by(&:trip_id)
  end

  def trip_loads
    @trip_loads ||= begin
      ids = inbound_trips.map(&:id) + scheduled_departures.map(&:id)
      Package.where(trip_id: ids).where.not(status: "delivered").left_joins(:order)
             .group(:trip_id).pluck(:trip_id, Arel.sql(PACKAGE_WEIGHT_SQL))
             .to_h { |trip_id, kg| [ trip_id, kg.to_f ] }
    end
  end
end
