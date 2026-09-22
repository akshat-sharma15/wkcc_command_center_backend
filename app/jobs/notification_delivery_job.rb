# Delivers one Notification via its channel adapter. Enqueued separately
# from Alert/Notification creation (see AlertEvaluationJob) so a Slack
# outage can never block or roll back Alert creation.
#
# Distinguishes two failure classes:
#   - configuration/logical failures (Slack not connected, no target
#     channel configured, Slack itself rejects the message) — permanent,
#     marked failed, NOT retried (retrying can't fix a logical error).
#   - transport failures (network/timeout) — transient, marked failed AND
#     re-raised so Sidekiq's own retry mechanism handles backoff/retry.
class NotificationDeliveryJob < ApplicationJob
  sidekiq_options retry: 5

  def perform(notification_id)
    notification = Notification.find_by(id: notification_id)
    return unless notification

    case notification.channel
    when "in_app" then deliver_in_app(notification)
    when "slack" then deliver_slack(notification)
    end
  end

  private

  def deliver_in_app(notification)
    RealtimeNotificationPublisher.publish(notification)
    notification.mark_delivered!
  rescue StandardError => e
    notification.mark_failed!(e.message)
    raise
  end

  def deliver_slack(notification)
    integration = Integration.find_by(provider: "slack")
    return notification.mark_failed!("Slack is not connected") unless integration&.connected? && integration.bot_token.present?

    channel = ENV["SLACK_NOTIFICATION_CHANNEL"]
    return notification.mark_failed!("SLACK_NOTIFICATION_CHANNEL is not configured") if channel.blank?

    result = SlackOauthClient.post_message(bot_token: integration.bot_token, channel: channel, text: slack_text(notification))

    if result["ok"]
      notification.mark_delivered!(external_reference: result["ts"])
    else
      notification.mark_failed!(result["error"] || "slack_error")
    end
  rescue SlackOauthClient::SlackApiError => e
    notification.mark_failed!(e.message)
    raise
  end

  def slack_text(notification)
    "*#{notification.title}*\n#{notification.message}"
  end
end
