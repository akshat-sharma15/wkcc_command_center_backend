# Append-only audit trail of Package#status changes, written by
# Package#record_status_transition (see package.rb) whenever status
# actually changes - never for unrelated field updates. Package#status
# remains the single current-state source of truth; this table only adds
# history for Shipment/Package/Delivery dashboard analytics. Immutable by
# design (no updated_at column).
class PackageStatusTransition < OperationsRecord
  belongs_to :package
  belongs_to :location, polymorphic: true, optional: true

  validates :to_status, presence: true
  validates :occurred_at, presence: true
end
