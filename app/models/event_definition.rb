# Configurable event types the Command Center can raise alerts against.
# Deliberately not an operational model in the "business entity" sense (no
# Hub/Vehicle/etc-style table) — group and event_type are just a
# controlled vocabulary. Moved from command_center to operations so
# AlertRule (also operations) can hold a real FK to it — see
# db/operations_migrate/20260922070000_create_operations_event_definitions.rb
# for the data migration and has_many :alert_rules below.
class EventDefinition < OperationsRecord
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

  has_many :alert_rules, dependent: :nullify

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
