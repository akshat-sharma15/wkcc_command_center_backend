# Append-only operational history for the Fleet dashboard (e.g. breakdowns,
# route deviations) - not connected to EventDefinition/Alert, and not a
# generic event framework. event_type stays a plain string so new event
# types can be added without a schema change.
class VehicleOperationEvent < OperationsRecord
  EVENT_TYPES = %w[
    BREAKDOWN
    BREAKDOWN_RESOLVED
    ROUTE_DEVIATION
    ROUTE_DEVIATION_RESOLVED
  ].freeze

  belongs_to :vehicle
  belongs_to :trip, optional: true

  validates :event_type, presence: true
  validates :occurred_at, presence: true
end
