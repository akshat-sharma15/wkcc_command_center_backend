# Append-only operational history for the Hub Operations dashboard (gate-in,
# unloading, scanning, sorting, loading, dispatch). Deliberately separate
# from EventDefinition/Alert - this is analytics data, not part of the
# alerting system - and not a generic event framework. event_type stays a
# plain string so the vocabulary can grow without a schema change.
class HubOperationsEvent < OperationsRecord
  EVENT_TYPES = %w[
    GATE_IN
    UNLOADING_STARTED
    UNLOADING_COMPLETED
    SCANNED
    SORTED
    LOADING_STARTED
    LOADING_COMPLETED
    DISPATCH_READY
    DEPARTED
  ].freeze

  belongs_to :hub
  belongs_to :vehicle, optional: true
  belongs_to :trip, optional: true
  belongs_to :package, optional: true

  validates :event_type, presence: true
  validates :occurred_at, presence: true
end
