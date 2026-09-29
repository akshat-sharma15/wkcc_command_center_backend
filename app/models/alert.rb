# A triggered occurrence of an AlertRule against one specific business
# record (group + record_id, resolved via AlertRule::ALERTABLE_MODELS —
# never a direct FK, since the target varies by group). Created/resolved
# by AlertEvaluationJob (see Alertable concern) or EventPublisher — never
# directly from a controller or model callback.
#
# Alerts are operational history: they are acknowledged/assigned/
# escalated/resolved through the lifecycle methods below, never deleted.
# Every lifecycle action is also appended to metadata["history"].
class Alert < OperationsRecord
  # open -> acknowledged -> in_progress (assigned / being worked) ->
  # escalated (handed to the secondary contact) -> resolved. Only "open"
  # takes part in the open-alert dedup index; every non-resolved status is
  # still an active incident (ACTIVE_STATUSES).
  enum :status, {
    open: "open", acknowledged: "acknowledged", in_progress: "in_progress",
    escalated: "escalated", resolved: "resolved"
  }, prefix: true
  ACTIVE_STATUSES = %w[open acknowledged in_progress escalated].freeze

  ASSIGNMENT_LEVELS = %w[primary secondary manual].freeze

  class TransitionError < StandardError; end

  belongs_to :alert_rule
  has_many :notifications, dependent: :destroy

  validates :group, presence: true
  validates :record_id, presence: true
  validates :field, presence: true
  validates :severity, presence: true
  validates :status, presence: true
  validates :triggered_at, presence: true
  validates :assignee_type, inclusion: { in: AlertRule::ASSIGNEE_TYPES, allow_blank: true }
  validates :assignment_level, inclusion: { in: ASSIGNMENT_LEVELS, allow_blank: true }

  before_create :assign_primary_from_rule

  def assignee
    assignee_type.present? && assignee_id.present? ? { type: assignee_type, id: assignee_id } : nil
  end

  # Open or escalated alerts can be acknowledged (an escalation is
  # acknowledged by the secondary contact).
  def acknowledge!(by:)
    raise TransitionError, "only an open or escalated alert can be acknowledged" unless status_open? || status_escalated?

    update_with_history!("acknowledged", by, {}, status: "acknowledged", acknowledged_at: Time.current, acknowledged_by: by)
  end

  # Assign and reassign are the same operation: the alert becomes
  # in_progress under the new current assignee. The rule's primary and
  # secondary contacts are never overwritten; history keeps from/to/who/when.
  def assign!(assignee_type:, assignee_id:, by:)
    ensure_not_resolved!("assigned")
    raise TransitionError, "assignee_type must be one of #{AlertRule::ASSIGNEE_TYPES.join(', ')}" unless AlertRule::ASSIGNEE_TYPES.include?(assignee_type.to_s)
    raise TransitionError, "assignee_id is required" if assignee_id.blank?

    to = { type: assignee_type.to_s, id: assignee_id.to_i }
    action = assignee ? "reassigned" : "assigned"
    update_with_history!(action, by, { from: assignee, to: to },
                         status: "in_progress", assignee_type: to[:type], assignee_id: to[:id],
                         assignment_level: "manual", assigned_at: Time.current)
  end

  # Hands the alert to the rule's secondary point of contact. One level of
  # escalation exists (primary -> secondary), matching AlertRule's two
  # configured assignee levels.
  def escalate!(by:)
    ensure_not_resolved!("escalated")
    secondary = alert_rule.assignee_for(:secondary)
    raise TransitionError, "the alert rule has no secondary assignee to escalate to" unless secondary
    raise TransitionError, "the alert is already escalated to the secondary assignee" if assignment_level == "secondary"

    update_with_history!("escalated", by, { from: assignee, to: secondary },
                         status: "escalated", assignee_type: secondary[:type], assignee_id: secondary[:id],
                         assignment_level: "secondary", assigned_at: Time.current,
                         escalated_at: Time.current, escalated_by: by,
                         escalation_level: escalation_level + 1)
  end

  def resolve!(by:, note: nil)
    ensure_not_resolved!("resolved")

    update_with_history!("resolved", by, { note: note.presence },
                         status: "resolved", resolved_at: Time.current, resolved_by: by,
                         resolution_note: note.presence)
  end

  # Minutes after which a still-unacknowledged alert is due for escalation
  # (per its rule), or nil when no escalation window is configured.
  def escalation_due_at
    minutes = alert_rule.escalation_after_minutes
    minutes && triggered_at + minutes.minutes
  end

  def active?
    ACTIVE_STATUSES.include?(status)
  end

  private

  def assign_primary_from_rule
    return if assignee.present?

    primary = alert_rule&.assignee_for(:primary)
    return unless primary

    self.assignee_type = primary[:type]
    self.assignee_id = primary[:id]
    self.assignment_level = "primary"
    self.assigned_at = Time.current
  end

  def ensure_not_resolved!(action)
    raise TransitionError, "a resolved alert cannot be #{action}" if status_resolved?
  end

  def update_with_history!(action, actor_id, details = {}, **attributes)
    entry = { action: action, actor_id: actor_id, at: Time.current.iso8601 }.merge(details.compact)
    with_lock do
      history = Array(metadata&.dig("history")) + [ entry.as_json ]
      update!(attributes.merge(metadata: (metadata || {}).merge("history" => history)))
    end
    self
  end
end
