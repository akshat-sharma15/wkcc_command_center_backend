class Package < OperationsRecord
  include Alertable

  belongs_to :trip, optional: true
  belongs_to :location, polymorphic: true
  belongs_to :order, optional: true
  has_many :package_status_transitions, dependent: :destroy

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

  # Isolated from Alertable's own after_commit hook above - this only
  # writes an audit row to package_status_transitions and never touches
  # alerting. Fires solely when `status` itself changed, never for
  # unrelated field updates (see CreatePackageStatusTransitions migration).
  after_commit :record_status_transition, on: :update

  private

  def record_status_transition
    return unless previous_changes.key?("status")

    from_status, to_status = previous_changes["status"]
    package_status_transitions.create!(
      from_status: from_status,
      to_status: to_status,
      occurred_at: Time.current,
      location_type: location_type,
      location_id: location_id
    )
  end
end
