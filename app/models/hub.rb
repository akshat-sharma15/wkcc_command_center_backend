class Hub < OperationsRecord
  include Alertable

  has_many :workforce_members, dependent: :restrict_with_error
  has_many :vehicles, dependent: :restrict_with_error
  has_many :outbound_trips, class_name: "Trip", foreign_key: :origin_hub_id, inverse_of: :origin_hub, dependent: :restrict_with_error
  has_many :inbound_trips, class_name: "Trip", foreign_key: :destination_hub_id, inverse_of: :destination_hub, dependent: :restrict_with_error
  has_many :packages, as: :location, dependent: :restrict_with_error

  # Fleet Monitoring POC addition (additive - the existing `location`
  # string column above is untouched). Named `geo_location` to avoid
  # clashing with the existing `location` string attribute and the
  # `packages ... as: :location` polymorphic association. Hubs are
  # deliberately not associated with a Vendor - only vehicles are.
  belongs_to :geo_location, class_name: "Location", foreign_key: :location_id, inverse_of: :hubs, optional: true

  enum :operational_status, { active: "active", degraded: "degraded", closed: "closed" }, prefix: true

  validates :name, presence: true
  validates :code, presence: true, uniqueness: true
  validates :capacity, :parking_capacity, :available_parking,
            numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
end
