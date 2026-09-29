# Publishes one of the advanced incidents (IncidentCatalog) by its stable
# key - a thin front door over EventPublisher, which remains the only
# thing that creates event Alerts. Also appends the matching row to the
# existing operational history (VehicleOperationEvent) so fleet
# dashboards count the breakdown/deviation like any other.
class IncidentPublisher
  class UnknownIncident < StandardError; end

  OPERATION_EVENT_TYPES = {
    IncidentCatalog::VEHICLE_FAILURE => "BREAKDOWN",
    IncidentCatalog::ROUTE_DIVERSION => "ROUTE_DEVIATION"
  }.freeze

  def self.publish(key, entity_id:, payload: {})
    raise UnknownIncident, "unknown incident '#{key}'" unless IncidentCatalog.advanced?(key)

    event_definition = IncidentCatalog.event_definition(key)
    raise UnknownIncident, "EventDefinition '#{key}' is not set up (run scripts/alerts/03_setup_event_definitions.rb)" unless event_definition

    entity_type = IncidentCatalog.definition(key)[:entity_type]
    record_operation_event(key, entity_id, payload)
    EventPublisher.publish(event_definition: event_definition, entity_type: entity_type, entity_id: entity_id, payload: payload)
  end

  def self.record_operation_event(key, entity_id, payload)
    event_type = OPERATION_EVENT_TYPES[key]
    return unless event_type

    vehicle_id, trip_id = if key == IncidentCatalog::ROUTE_DIVERSION
      RouteDiversion.where(id: entity_id).pick(:vehicle_id, :trip_id)
    else
      [ entity_id, Trip.where(vehicle_id: entity_id, status: EtaImpactService::MOVING_TRIP_STATUSES).order(departure_at: :desc).pick(:id) ]
    end
    return unless vehicle_id && Vehicle.exists?(vehicle_id)

    VehicleOperationEvent.create!(vehicle_id: vehicle_id, trip_id: trip_id, event_type: event_type,
                                  occurred_at: Time.current, metadata: { incident_key: key, payload: payload })
  end
  private_class_method :record_operation_event
end
