# The three advanced operational incidents the backend publishes against.
# Each is an ordinary EventDefinition (no incident-specific tables); the
# stable `key` is how code finds it, `name` is what users see, and
# group/event_type come from EventDefinition::GROUPS_AND_TYPES' existing
# vocabulary. `entity_type` is what EventPublisher records for the
# occurrence (free-text, see EventPublisher).
module IncidentCatalog
  VEHICLE_FAILURE = "vehicle.failure".freeze
  HUB_EXTRA_VEHICLE_REQUEST = "hub.extra_vehicle_request".freeze
  ROUTE_DIVERSION = "route.diversion".freeze

  DEFINITIONS = {
    VEHICLE_FAILURE => {
      name: "Truck Failure",
      group: "Fleet / Transport",
      event_type: "Need Vehicle Replacement",
      entity_type: "vehicles"
    },
    HUB_EXTRA_VEHICLE_REQUEST => {
      name: "Extra Vehicle Request",
      group: "Hubs",
      event_type: "Capacity",
      entity_type: "hubs"
    },
    ROUTE_DIVERSION => {
      name: "Route Diversion",
      group: "Fleet / Transport",
      event_type: "Route Diversion",
      entity_type: "route_diversions"
    }
  }.freeze

  module_function

  def keys
    DEFINITIONS.keys
  end

  def advanced?(key)
    DEFINITIONS.key?(key.to_s)
  end

  def definition(key)
    DEFINITIONS.fetch(key.to_s)
  end

  def event_definition(key)
    EventDefinition.find_by(key: key.to_s)
  end

  # Idempotent: finds by key, then adopts an existing same-named
  # definition (giving it the key) before ever creating a new one.
  def ensure_event_definitions!
    DEFINITIONS.map do |key, attrs|
      record = EventDefinition.find_by(key: key) || EventDefinition.find_by(name: attrs[:name]) || EventDefinition.new
      record.assign_attributes(key: key, name: attrs[:name], group: attrs[:group], event_type: attrs[:event_type])
      record.save! if record.changed?
      record
    end
  end
end
