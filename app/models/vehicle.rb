class Vehicle < OperationsRecord
  include Alertable

  belongs_to :hub
  belongs_to :driver, class_name: "WorkforceMember", optional: true
  has_many :trips, dependent: :restrict_with_error

  enum :status, { active: "active", maintenance: "maintenance", out_of_service: "out_of_service" }, prefix: true

  validates :number, presence: true, uniqueness: true
  validates :vehicle_type, presence: true
  validates :capacity, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
end
