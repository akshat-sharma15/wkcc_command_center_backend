# Shipment/Package/Delivery dashboard data foundation. The minimal
# customer-facing concept above Package - no Customer/Consignee/Invoice/
# OrderItem modeling yet (out of scope for this MVP; see ARCHITECTURE.md
# data-gap notes). Intentionally has no relationship to the Alert system.
class Order < OperationsRecord
  STATUSES = %w[pending processing in_transit delivered cancelled].freeze

  belongs_to :origin_hub, class_name: "Hub", optional: true
  belongs_to :destination_hub, class_name: "Hub", optional: true
  has_many :packages, dependent: :nullify

  enum :status, STATUSES.index_by(&:itself), prefix: true

  validates :order_number, presence: true, uniqueness: true
  validates :package_count, numericality: { greater_than_or_equal_to: 0 }
  validates :total_weight, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
end
