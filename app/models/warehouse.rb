class Warehouse < OperationsRecord
  has_many :packages, as: :location, dependent: :restrict_with_error

  enum :status, { active: "active", inactive: "inactive", closed: "closed" }, prefix: true

  validates :name, presence: true
  validates :code, presence: true, uniqueness: true
  validates :capacity, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
end
