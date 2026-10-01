# An actual operational diversion of a vehicle's in-transit trip (not an
# alert model - the incident Alert is created through the normal
# EventPublisher pipeline and linked via alert_id). Paths are ordered
# waypoint lists since there is no Route model; see CreateRouteDiversions.
class RouteDiversion < OperationsRecord
  STATUSES = %w[active resolved cancelled].freeze

  belongs_to :vehicle
  belongs_to :trip
  belongs_to :alert, optional: true

  enum :status, STATUSES.index_by(&:itself), prefix: true

  validates :reason, presence: true
  validates :diverted_at, presence: true
  validates :traffic_factor, numericality: { greater_than: 0 }
  validate :paths_are_waypoint_lists
  validate :trip_belongs_to_vehicle

  scope :active, -> { where(status: "active") }

  def resolve!
    update!(status: "resolved", resolved_at: Time.current)
  end

  private

  def paths_are_waypoint_lists
    { original_path: original_path, diverted_path: diverted_path }.each do |attribute, path|
      valid = path.is_a?(Array) && path.size >= 2 && path.all? { |point| GeoDistance.point?(point) }
      errors.add(attribute, "must list at least two waypoints with numeric lat/lng") unless valid
    end
  end

  def trip_belongs_to_vehicle
    return if trip.nil? || vehicle_id.nil? || trip.vehicle_id == vehicle_id

    errors.add(:trip_id, "does not belong to this vehicle")
  end
end
