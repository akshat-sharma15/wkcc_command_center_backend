# Configurable event types the Command Center can raise alerts against.
# Deliberately not an operational model (no Hub/Vehicle/etc table) — group
# and event_type are just a controlled vocabulary. Real operational entities
# are connected later via entity_type/entity_id on an EventOccurrence
# (Stage 4+), never a direct association from here.
class EventDefinition < CommandCenterRecord
  GROUPS_AND_TYPES = {
    "Hubs" => [
      "Inbound Truck",
      "Outbound Truck",
      "Parking Space",
      "Capacity"
    ],
    "Fleet / Transport" => [
      "Failure of Truck with Goods Damaged",
      "Need Vehicle Replacement",
      "Route Diversion",
      "Cancel Departure",
      "Accident"
    ],
    "Workforce" => [
      "Shift Change",
      "Low Attendance"
    ],
    "Sales" => [
      "Low Inbound Calls",
      "Low Outbound Calls"
    ],
    "Finance" => [
      "Payment Dues"
    ]
  }.freeze

  has_many :alerts, dependent: :restrict_with_error

  validates :name, presence: true, uniqueness: true
  validates :group, presence: true, inclusion: { in: GROUPS_AND_TYPES.keys }
  validates :event_type, presence: true
  validate :event_type_must_belong_to_group

  private

  def event_type_must_belong_to_group
    return if group.blank? || event_type.blank?
    return unless GROUPS_AND_TYPES.key?(group)

    allowed_types = GROUPS_AND_TYPES.fetch(group)
    return if allowed_types.include?(event_type)

    errors.add(:event_type, "'#{event_type}' is not valid for group '#{group}'")
  end
end
