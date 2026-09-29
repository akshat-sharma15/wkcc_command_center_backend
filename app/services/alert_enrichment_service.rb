# Enriches an event-triggered Alert for one of the advanced incidents
# (IncidentCatalog) with an operational snapshot under
# metadata["incident"]: vehicle, driver, route, current/next hub, ETA,
# delay, waybill/package/order counts, revenue and SLA risk, plus map deep
# links. Called by EventPublisher between Alert creation and notification,
# so the notification payloads (in-app/SSE and Slack) carry the snapshot.
#
# The snapshot is point-in-time incident context, not a copy of the
# relational data - ids are kept alongside the display values so callers
# can always go back to the live records. Enrichment never blocks the
# alert: any failure is recorded as incident.enrichment_error and the
# notification still goes out.
class AlertEnrichmentService
  def initialize(alert, event_definition)
    @alert = alert
    @event_definition = event_definition
    @payload = (alert.metadata || {})["payload"] || {}
  end

  def self.enrich!(alert, event_definition)
    new(alert, event_definition).enrich!
  end

  def enrich!
    key = @event_definition.key
    return @alert unless IncidentCatalog.advanced?(key)

    incident = { key: key, title: @event_definition.name, severity: @alert.severity }
    incident.merge!(build(key))
    store(incident)
  rescue StandardError => e
    Rails.logger.error("[AlertEnrichmentService] alert=#{@alert.id} #{e.class}: #{e.message}")
    store(key: key, title: @event_definition.name, severity: @alert.severity, enrichment_error: e.message)
  end

  private

  def build(key)
    case key
    when IncidentCatalog::VEHICLE_FAILURE then vehicle_failure
    when IncidentCatalog::HUB_EXTRA_VEHICLE_REQUEST then extra_vehicle_request
    when IncidentCatalog::ROUTE_DIVERSION then route_diversion
    end
  end

  def store(incident)
    @alert.update!(metadata: (@alert.metadata || {}).merge("incident" => incident.as_json))
    @alert
  end

  # --- vehicle.failure ---------------------------------------------------
  # Delay is only known when the reporter supplies estimated_repair_minutes;
  # otherwise predicted ETA is unavailable and every open waybill on the
  # trip counts as at risk (see RevenueRiskService).
  def vehicle_failure
    vehicle = Vehicle.includes(:driver, :current_geo_location, hub: :geo_location).find(@alert.record_id)
    trip = current_trip(vehicle)
    repair_minutes = @payload["estimated_repair_minutes"].presence&.to_i
    eta = trip && EtaImpactService.new(trip, vehicle: vehicle)
    planned = trip&.expected_arrival_at
    predicted = if repair_minutes && eta
      (eta.predicted_eta || planned)&.+(repair_minutes.minutes)
    end

    vehicle_context(vehicle, trip, eta).merge(
      failure_type: @payload["failure_type"],
      planned_eta: planned&.iso8601,
      predicted_eta: predicted&.iso8601,
      delay_minutes: predicted && planned ? [ ((predicted - planned) / 60).round, 0 ].max : nil,
      **impact(trip, predicted),
      summary: [ "Truck #{vehicle.number} has failed#{@payload['failure_type'].present? ? " (#{@payload['failure_type']})" : ''}",
                 trip && "on #{trip.origin_hub.name} → #{trip.destination_hub.name}" ].compact.join(" ") + "."
    )
  end

  # --- hub.extra_vehicle_request ---------------------------------------
  def extra_vehicle_request
    hub = Hub.includes(:geo_location).find(@alert.record_id)
    cutoff = @payload["cutoff"].presence && Time.zone.parse(@payload["cutoff"].to_s)
    load = HubLoadService.new(hub, cutoff: cutoff).as_json
    suggested = suggested_additional_vehicles(hub, load)
    requested = @payload["requested_vehicle_count"].presence&.to_i || suggested

    {
      hub: load[:hub],
      reason: @payload["reason"],
      priority: @payload["priority"],
      requested_vehicle_count: requested,
      suggested_additional_vehicles: suggested,
      reported: @payload.slice("current_inbound_count", "current_outbound_count", "projected_load", "available_vehicle_count"),
      hub_load: load,
      inbound_vehicle_count: load[:inbound_vehicle_count],
      outbound_vehicle_count: load[:outbound_vehicle_count],
      projected_load_kg: load[:projected_load_kg],
      capacity_kg: load[:capacity_kg],
      projected_utilization_pct: load[:projected_utilization_pct],
      available_vehicle_count: load[:available_vehicle_count],
      links: { hub: IncidentLinks.hub(hub.code), hub_outbound: IncidentLinks.hub(hub.code, direction: "outbound") },
      summary: "#{hub.name} requests #{requested || 'additional'} extra vehicle#{requested == 1 ? '' : 's'}" \
               "#{@payload['reason'].present? ? ": #{@payload['reason']}" : ''}."
    }
  end

  # Vehicles needed to move the outbound load that the hub's available
  # (parked, serviceable) fleet can't carry, sized by that fleet's average
  # capacity. nil when there is no vehicle capacity to size against.
  def suggested_additional_vehicles(hub, load)
    shortfall = load[:outbound_load_kg] - load[:available_vehicle_capacity_kg]
    return 0 unless shortfall.positive?

    average = Vehicle.where(hub_id: hub.id).where.not(capacity: nil).average(:capacity)&.to_f
    average&.positive? ? (shortfall / average).ceil : nil
  end

  # --- route.diversion ---------------------------------------------------
  # The diversion's persisted impact (RouteDiversionImpactService#apply!,
  # run by RouteDiversionsController before publishing) is the snapshot.
  def route_diversion
    diversion = RouteDiversion.includes(:trip, vehicle: [ :driver, :current_geo_location ]).find(@alert.record_id)
    impact = diversion.impact_snapshot.presence || RouteDiversionImpactService.new(diversion).apply!.as_json
    vehicle = diversion.vehicle
    trip = diversion.trip
    eta = EtaImpactService.new(trip, vehicle: vehicle, diversion: diversion)

    vehicle_context(vehicle, trip, eta).merge(
      diversion_id: diversion.id,
      reason: diversion.reason,
      original_route: diversion.original_path,
      diverted_route: diversion.diverted_path,
      original_route_label: route_label(diversion.original_path),
      diverted_route_label: route_label(diversion.diverted_path),
      additional_distance_km: impact["additional_distance_km"],
      planned_eta: impact["original_eta"],
      predicted_eta: impact["revised_eta"],
      delay_minutes: impact["estimated_delay_minutes"],
      fuel_impact_litres: impact["fuel_impact_litres"],
      waybill_count: impact["affected_waybills"],
      package_count: impact["affected_packages"],
      order_count: impact["affected_orders"],
      revenue_risk: impact["revenue_risk"],
      revenue: impact["revenue"],
      sla_risk: impact["sla_risk"],
      destination_hub_impact: impact["destination_hub_impact"],
      hub_congestion_risk: impact["hub_congestion_risk"],
      missed_departure_risk: impact["missed_departure_risk"],
      unavailable: impact["unavailable"],
      links: {
        vehicle: IncidentLinks.vehicle(vehicle.number),
        route: IncidentLinks.route(vehicle.number, diversion_id: diversion.id),
        hub: IncidentLinks.hub(trip.destination_hub.code, direction: "inbound")
      },
      summary: "Truck #{vehicle.number} diverted: #{route_label(diversion.diverted_path)} " \
               "(+#{impact['additional_distance_km']} km#{impact['estimated_delay_minutes'] ? ", +#{impact['estimated_delay_minutes']} min" : ''})."
    )
  end

  # --- shared ------------------------------------------------------------
  def current_trip(vehicle)
    vehicle.trips.where(status: EtaImpactService::MOVING_TRIP_STATUSES)
           .includes(origin_hub: :geo_location, destination_hub: :geo_location)
           .order(departure_at: :desc).first
  end

  def vehicle_context(vehicle, trip, eta)
    {
      vehicle: { id: vehicle.id, number: vehicle.number, status: vehicle.status, vehicle_type: vehicle.vehicle_type, capacity_kg: vehicle.capacity },
      driver: vehicle.driver && { id: vehicle.driver.id, name: vehicle.driver.name, phone: vehicle.driver.phone_number },
      trip_id: trip&.id,
      route: trip && {
        origin: EtaImpactService.hub_point(trip.origin_hub),
        destination: EtaImpactService.hub_point(trip.destination_hub),
        planned_route: eta&.planned_route,
        current_route: eta&.current_route,
        label: "#{trip.origin_hub.name} → #{trip.destination_hub.name}"
      },
      current_hub: trip ? EtaImpactService.hub_point(trip.origin_hub) : EtaImpactService.hub_point(vehicle.hub),
      next_hub: trip && EtaImpactService.hub_point(trip.destination_hub),
      links: {
        vehicle: IncidentLinks.vehicle(vehicle.number),
        route: trip && IncidentLinks.route(vehicle.number),
        hub: IncidentLinks.hub((trip&.destination_hub || vehicle.hub).code)
      }.compact
    }
  end

  def impact(trip, revised_arrival)
    waybills = WaybillImpactService.new(trip, revised_arrival: revised_arrival)
    revenue = RevenueRiskService.new(waybills.waybills, revised_arrival: revised_arrival)
    {
      waybill_count: waybills.waybills.size,
      package_count: waybills.packages.size,
      order_count: waybills.orders.size,
      waybill_impact: waybills.as_json,
      revenue_risk: revenue.revenue_risk&.to_f,
      revenue: revenue.as_json,
      sla_risk: waybills.sla_risk
    }
  end

  def route_label(path)
    Array(path).map { |point| point["name"] || point[:name] }.compact.join(" → ")
  end
end
