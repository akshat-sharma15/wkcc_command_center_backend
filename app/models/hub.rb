class Hub < OperationsRecord
  has_many :workforce_members, dependent: :restrict_with_error
  has_many :vehicles, dependent: :restrict_with_error
  has_many :outbound_trips, class_name: "Trip", foreign_key: :origin_hub_id, inverse_of: :origin_hub, dependent: :restrict_with_error
  has_many :inbound_trips, class_name: "Trip", foreign_key: :destination_hub_id, inverse_of: :destination_hub, dependent: :restrict_with_error
  has_many :packages, as: :location, dependent: :restrict_with_error

  enum :operational_status, { active: "active", degraded: "degraded", closed: "closed" }, prefix: true

  validates :name, presence: true
  validates :code, presence: true, uniqueness: true
  validates :capacity, :parking_capacity, :available_parking,
            numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
end
