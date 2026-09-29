class Vehicle < OperationsRecord
  include Alertable

  belongs_to :hub
  belongs_to :driver, class_name: "WorkforceMember", optional: true
  has_many :trips, dependent: :restrict_with_error
  has_many :waybills, dependent: :restrict_with_error
  has_many :route_diversions, dependent: :restrict_with_error

  # Fleet Monitoring POC additions (additive - the existing `current_location`
  # string and `vendor` string columns above are untouched). Named
  # `current_geo_location`/`vendor_account` rather than `current_location`/
  # `vendor` so they don't clobber the existing free-text attribute readers
  # (an association with the same name as a column overrides that column's
  # reader/writer, which would break the existing VehicleSerializer/
  # VehiclesController that read/assign the plain string).
  belongs_to :current_geo_location, class_name: "Location", foreign_key: :current_location_id, optional: true
  belongs_to :vendor_account, class_name: "Vendor", foreign_key: :vendor_id, inverse_of: :vehicles, optional: true

  enum :status, { active: "active", maintenance: "maintenance", out_of_service: "out_of_service" }, prefix: true

  validates :number, presence: true, uniqueness: true
  validates :vehicle_type, presence: true
  validates :capacity, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

  scope :fleet_monitoring_poc, -> { where(fleet_monitoring_poc: true) }
end
