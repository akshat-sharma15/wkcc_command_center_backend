# Creates a RouteDiversion the one supported way: persist it, calculate
# and store its impact (RouteDiversionImpactService), then publish the
# route.diversion incident through the normal EventPublisher pipeline and
# link the resulting Alert. Used by POST /api/v1/route-diversions and the
# seed script, so both produce identical records.
class RouteDiversionCreator
  def self.create!(vehicle:, trip:, reason:, diverted_path:, original_path: nil, traffic_factor: 1.0,
                   original_distance_km: nil, diverted_distance_km: nil, publish: true)
    eta = EtaImpactService.new(trip, vehicle: vehicle, diversion: nil)
    diversion = RouteDiversion.new(
      vehicle: vehicle, trip: trip, reason: reason, status: "active", diverted_at: Time.current,
      traffic_factor: traffic_factor.presence || 1.0,
      original_path: original_path.presence || eta.planned_route,
      diverted_path: diverted_path
    )

    RouteDiversion.transaction do
      diversion.save!
      RouteDiversionImpactService.new(diversion, original_distance_km: original_distance_km,
                                                 diverted_distance_km: diverted_distance_km).apply!
    end

    if publish
      alert = IncidentPublisher.publish(IncidentCatalog::ROUTE_DIVERSION, entity_id: diversion.id, payload: { reason: reason }).first
      diversion.update!(alert: alert) if alert
    end
    diversion
  end
end
