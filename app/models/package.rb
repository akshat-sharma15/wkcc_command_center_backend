class Package < OperationsRecord
  include Alertable

  belongs_to :trip, optional: true
  belongs_to :location, polymorphic: true

  enum :status, {
    pending: "pending",
    in_transit: "in_transit",
    received: "received",
    damaged: "damaged",
    short: "short",
    delivered: "delivered"
  }, prefix: true

  validates :identifier, presence: true, uniqueness: true
  validates :expected_quantity, :received_quantity, :damaged_quantity, :short_quantity,
            numericality: { greater_than_or_equal_to: 0 }
  validates :location_type, inclusion: { in: %w[Warehouse Hub] }
end
