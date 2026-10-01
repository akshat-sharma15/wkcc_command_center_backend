# Operational impact of a RouteDiversion, from existing data only:
#
#   original/diverted distance  operator-supplied road distance when the
#                               diversion already carries one, otherwise
#                               great-circle over the waypoints
#   planned pace                original distance / trip's planned duration
#   delay_minutes               (diverted_km x traffic_factor - original_km)
#                               / planned pace, never negative
#   revised_eta                 trip.expected_arrival_at + delay
#   fuel_impact_litres          additional_km / vehicle.fuel_efficiency_kmpl
#   waybills/packages/orders    WaybillImpactService on the trip
#   revenue_risk                RevenueRiskService
#   affected_vehicles           this vehicle + other moving trips on the
#                               same origin -> destination corridor
#   hub_congestion_risk         HubLoadService at the destination, with the
#                               revised arrival as cutoff
#   missed_departure_risk       this vehicle's next scheduled trip from the
#                               destination hub departs before revised_eta
#
# Any figure whose inputs don't exist is nil and listed in `unavailable`.
# #apply! persists the numeric snapshot onto the diversion.
class RouteDiversionImpactService
  def initialize(diversion, original_distance_km: nil, diverted_distance_km: nil, now: Time.current)
    @diversion = diversion
    @supplied_distances = { original_distance_km: original_distance_km, diverted_distance_km: diverted_distance_km }
    @trip = diversion.trip
    @vehicle = diversion.vehicle
    @now = now
  end

  def call
    @call ||= build
  end

  def apply!
    result = call
    @diversion.update!(
      original_distance_km: result[:original_distance_km],
      diverted_distance_km: result[:diverted_distance_km],
      additional_distance_km: result[:additional_distance_km],
      original_eta: result[:original_eta],
      revised_eta: result[:revised_eta],
      delay_minutes: result[:estimated_delay_minutes],
      fuel_impact_litres: result[:fuel_impact_litres],
      affected_waybills: result[:affected_waybills],
      affected_packages: result[:affected_packages],
      affected_orders: result[:affected_orders],
      revenue_risk: result[:revenue_risk],
      impact_snapshot: result.as_json
    )
    result
  end

  private

  def build
    unavailable = []
    original_km = distance(:original_distance_km, @diversion.original_path)
    diverted_km = distance(:diverted_distance_km, @diversion.diverted_path)
    additional_km = (diverted_km - original_km).round(2)

    delay = delay_minutes(original_km, diverted_km)
    unavailable << "estimated_delay_minutes: trip has no planned departure/arrival to derive pace from" if delay.nil?
    original_eta = @trip.expected_arrival_at
    revised_eta = original_eta && delay ? original_eta + delay.minutes : nil

    fuel = fuel_litres(additional_km)
    unavailable << "fuel_impact_litres: vehicle has no fuel_efficiency_kmpl" if fuel.nil?

    waybill_impact = WaybillImpactService.new(@trip, revised_arrival: revised_eta)
    revenue = RevenueRiskService.new(waybill_impact.waybills, revised_arrival: revised_eta)
    unavailable << "revenue_risk: #{revenue.as_json[:unavailable]}" if revenue.revenue_risk.nil?

    hub_load = HubLoadService.new(@trip.destination_hub, cutoff: revised_eta || original_eta || @now, now: @now)
    hub_json = hub_load.as_json
    unavailable << "hub_congestion_risk: #{hub_json[:unavailable]}" if hub_json[:unavailable]

    {
      diversion_id: @diversion.id,
      vehicle: { id: @vehicle.id, number: @vehicle.number },
      trip_id: @trip.id,
      original_route: @diversion.original_path,
      diverted_route: @diversion.diverted_path,
      distance_basis: distance_basis,
      original_distance_km: original_km,
      diverted_distance_km: diverted_km,
      additional_distance_km: additional_km,
      traffic_factor: @diversion.traffic_factor.to_f,
      planned_speed_kmph: planned_speed(original_km)&.round(1),
      estimated_delay_minutes: delay,
      original_eta: original_eta,
      revised_eta: revised_eta,
      fuel_impact_litres: fuel,
      affected_vehicles: affected_vehicles,
      affected_waybills: waybill_impact.waybills.size,
      affected_packages: waybill_impact.packages.size,
      affected_orders: waybill_impact.orders.size,
      waybill_impact: waybill_impact.as_json,
      sla_risk: waybill_impact.sla_risk,
      revenue: revenue.as_json,
      revenue_risk: revenue.revenue_risk&.to_f,
      destination_hub_impact: destination_hub_impact(hub_json, original_eta, revised_eta),
      hub_congestion_risk: hub_json[:congestion_risk],
      missed_departure_risk: missed_departure_risk(revised_eta),
      unavailable: unavailable
    }
  end

  # Operator-supplied road distances (e.g. from the dispatcher's routing
  # tool) win over the great-circle fallback. On a recalculation without
  # new input, previously supplied distances are reused.
  def distance(column, path)
    supplied = @supplied_distances[column] || (previously_supplied? ? @diversion.public_send(column) : nil)
    (supplied.presence&.to_f || GeoDistance.path_km(path)).round(2)
  end

  def previously_supplied?
    @diversion.impact_snapshot.is_a?(Hash) && @diversion.impact_snapshot["distance_basis"] == "operator_supplied"
  end

  def distance_basis
    supplied = @supplied_distances.values_at(:original_distance_km, :diverted_distance_km).all?(&:present?)
    supplied || previously_supplied? ? "operator_supplied" : "great_circle"
  end

  def planned_speed(original_km)
    return nil unless @trip.departure_at && @trip.expected_arrival_at

    hours = (@trip.expected_arrival_at - @trip.departure_at) / 3600.0
    hours.positive? && original_km.positive? ? original_km / hours : nil
  end

  def delay_minutes(original_km, diverted_km)
    speed = planned_speed(original_km)
    return nil unless speed

    extra_hours = (diverted_km * @diversion.traffic_factor.to_f - original_km) / speed
    [ (extra_hours * 60).round, 0 ].max
  end

  def fuel_litres(additional_km)
    efficiency = @vehicle.fuel_efficiency_kmpl&.to_f
    efficiency&.positive? ? (additional_km / efficiency).round(2) : nil
  end

  def affected_vehicles
    others = Trip.where(origin_hub_id: @trip.origin_hub_id, destination_hub_id: @trip.destination_hub_id,
                        status: EtaImpactService::MOVING_TRIP_STATUSES)
                 .where.not(id: @trip.id).includes(:vehicle).map { |trip| trip.vehicle.number }
    { count: 1 + others.size, vehicle_numbers: [ @vehicle.number, *others ] }
  end

  def destination_hub_impact(hub_json, original_eta, revised_eta)
    {
      hub: hub_json[:hub],
      planned_arrival: original_eta&.iso8601,
      revised_arrival: revised_eta&.iso8601,
      projected_load_kg_at_arrival: hub_json[:projected_load_kg],
      capacity_kg: hub_json[:capacity_kg],
      projected_utilization_pct: hub_json[:projected_utilization_pct],
      inbound_vehicle_count: hub_json[:inbound_vehicle_count]
    }
  end

  def missed_departure_risk(revised_eta)
    next_trip = Trip.status_scheduled.where(vehicle_id: @vehicle.id, origin_hub_id: @trip.destination_hub_id)
                    .where.not(departure_at: nil).order(:departure_at).first
    return { at_risk: false, reason: "no_scheduled_next_departure" } unless next_trip
    return { at_risk: nil, trip_id: next_trip.id, reason: "revised_eta_unknown" } unless revised_eta

    { at_risk: revised_eta > next_trip.departure_at, trip_id: next_trip.id, departure_at: next_trip.departure_at.iso8601 }
  end
end
