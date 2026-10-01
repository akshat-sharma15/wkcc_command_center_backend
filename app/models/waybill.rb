# Transport document for a consignment on a vehicle's trip. Its contents
# are existing Package rows (packages.waybill_id) and, through them, their
# Orders - customers are Order#customer_reference, never a copied table.
# See CreateWaybills for the column rationale.
class Waybill < OperationsRecord
  STATUSES = %w[draft issued in_transit delivered cancelled].freeze
  OPEN_STATUSES = %w[issued in_transit].freeze

  belongs_to :vehicle
  belongs_to :trip, optional: true
  belongs_to :origin_hub, class_name: "Hub"
  belongs_to :destination_hub, class_name: "Hub"
  has_many :packages, dependent: :nullify
  has_many :orders, -> { distinct }, through: :packages

  enum :status, STATUSES.index_by(&:itself), prefix: true

  validates :waybill_number, presence: true, uniqueness: true
  validates :total_packages, :total_orders, :customer_count, numericality: { greater_than_or_equal_to: 0 }
  validates :total_weight, :declared_value, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validate :destination_differs_from_origin

  scope :open, -> { where(status: OPEN_STATUSES) }

  # Recomputes the document totals from its actual packages/orders. A
  # package's weight is its order's total_weight apportioned across that
  # order's package_count (orders carry weight, packages do not).
  def recalculate_totals!
    rows = packages.left_joins(:order)
                   .pluck(:order_id, "orders.customer_reference", "orders.total_weight", "orders.package_count")
    weight = rows.sum { |_, _, total, count| total.to_f / [ count.to_i, 1 ].max }

    update!(
      total_packages: rows.size,
      total_orders: rows.filter_map(&:first).uniq.size,
      customer_count: rows.filter_map { |row| row[1] }.uniq.size,
      total_weight: weight.round(2)
    )
  end

  # Single customer reference when the waybill has exactly one consignee,
  # otherwise nil (callers show customer_count instead).
  def customer_reference
    refs = orders.distinct.pluck(:customer_reference).compact
    refs.one? ? refs.first : nil
  end

  private

  def destination_differs_from_origin
    return if origin_hub_id.blank? || origin_hub_id != destination_hub_id

    errors.add(:destination_hub_id, "must differ from origin hub")
  end
end
