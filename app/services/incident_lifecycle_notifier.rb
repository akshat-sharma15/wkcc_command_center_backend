# Notifies the people affected by an Alert LIFECYCLE action (assign,
# reassign, acknowledge, escalate, resolve).
#
# Why this exists: AlertNotifier fans an alert out once, at creation, to
# the RULE's recipients. Nothing afterwards created a Notification, so a
# user who was later assigned an incident received nothing at all - no
# in-app row, and no Slack message. RealtimeNotificationPublisher
# .publish_incident_update only reaches users who ALREADY have a
# Notification for that alert, and SlackIncidentSyncJob only re-renders
# messages that were already posted, so neither covered a new assignee.
#
# This adds no new delivery mechanism: it creates ordinary Notification
# rows and enqueues the existing NotificationDeliveryJob, which is what
# already performs in-app (RealtimeNotificationPublisher -> Redis -> SSE)
# and Slack (chat.postMessage) delivery. The Alert stays the single
# source of truth - no new alert is ever created for a state change.
#
# Channels come from the alert's own rule (AlertRule#notification_channels),
# the same policy AlertNotifier uses, so this never invents its own.
class IncidentLifecycleNotifier
  # Actions whose audience is "whoever is already involved" rather than a
  # specific assignee - the assigner/original recipients learn that the
  # incident moved on.
  BROADCAST_ACTIONS = %w[acknowledged escalated resolved].freeze

  def self.notify(alert, action:, actor_id:, previous_assignee: nil)
    new(alert, action: action, actor_id: actor_id, previous_assignee: previous_assignee).notify
  end

  def initialize(alert, action:, actor_id:, previous_assignee: nil)
    @alert = alert
    @action = action.to_s
    @actor_id = actor_id&.to_i
    @previous_assignee = previous_assignee
  end

  # Returns the Notification rows it created (may be empty - e.g. the
  # only person to inform is the one who performed the action).
  def notify
    return [] unless @alert.alert_rule&.notify?

    channels = @alert.alert_rule.notification_channels & Notification::CHANNELS
    return [] if channels.empty?

    recipient_ids.flat_map do |user_id|
      channels.map { |channel| deliver(user_id, channel) }
    end.compact
  end

  private

  # Never notify the person who just performed the action - they know.
  def recipient_ids
    ids = case @action
    when "assigned", "reassigned" then [ assignee_id, previous_assignee_id ]
    when *BROADCAST_ACTIONS then already_involved_ids
    else []
    end
    ids.compact.uniq - [ @actor_id ].compact
  end

  def assignee_id
    @alert.assignee_type == "user" ? @alert.assignee_id : nil
  end

  def previous_assignee_id
    return nil unless @previous_assignee.is_a?(Hash)

    @previous_assignee[:type].to_s == "user" ? @previous_assignee[:id]&.to_i : nil
  end

  # Everyone who has already been told about this incident, plus its
  # current assignee (who may have been assigned before this action).
  def already_involved_ids
    @alert.notifications.distinct.pluck(:recipient_user_id) + [ assignee_id ]
  end

  def deliver(user_id, channel)
    notification = Notification.create!(
      alert: @alert,
      recipient_user_id: user_id,
      channel: channel,
      status: "pending",
      title: title,
      message: message,
      metadata: metadata
    )
    NotificationDeliveryJob.perform_async(notification.id)
    notification
  end

  # Keeps the incident's own name so the item groups with the incident it
  # belongs to; the lifecycle sentence is the message.
  def title
    @alert.alert_rule.name
  end

  # "Incident assigned to X" / "Incident acknowledged by X" - section 9's
  # wording, with the incident's own summary kept after it so the row
  # still says WHICH incident moved.
  def message
    [ headline, @alert.metadata&.dig("incident", "summary") ].compact.join(" — ")
  end

  def headline
    case @action
    when "assigned" then "Incident assigned to #{principal_name(@alert.assignee)}"
    when "reassigned" then "Incident reassigned from #{principal_name(@previous_assignee)} to #{principal_name(@alert.assignee)}"
    when "acknowledged" then "Incident acknowledged by #{user_name(@actor_id)}"
    when "escalated" then "Incident escalated to #{principal_name(@alert.assignee)}"
    when "resolved" then "Incident resolved by #{user_name(@actor_id)}"
    else "Incident #{@action}"
    end
  end

  def metadata
    {
      alert_id: @alert.id,
      alert_rule_id: @alert.alert_rule_id,
      rule_name: @alert.alert_rule.name,
      severity: @alert.severity,
      record_id: @alert.record_id,
      lifecycle_action: @action,
      actor_id: @actor_id,
      actor_name: user_name(@actor_id),
      assigned_to: @alert.assignee,
      assigned_to_name: principal_name(@alert.assignee),
      previous_assignee: @previous_assignee,
      status: @alert.status,
      at: Time.current.iso8601,
      incident: IncidentNotificationPresenter.new(@alert).as_json
    }
  end

  def principal_name(principal)
    return "unassigned" unless principal.is_a?(Hash) && principal[:id]

    SupersetDirectory.resolve_principal(principal[:type], principal[:id])&.dig(:name) ||
      "#{principal[:type]} ##{principal[:id]}"
  end

  def user_name(user_id)
    return "the system" if user_id.blank?

    SupersetDirectory.find_user(user_id)&.dig(:name) || "user ##{user_id}"
  end
end
