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

    result = SlackOauthClient.post_message(bot_token: integration.bot_token, channel: channel, text: slack_text(notification), blocks: slack_blocks(notification))
    result = retry_after_joining(integration.bot_token, channel, notification) if result["error"] == "not_in_channel"

    if result["ok"]
      notification.mark_delivered!(external_reference: result["ts"])
      # chat.update needs the channel ID Slack resolved the name to.
      notification.update!(metadata: (notification.metadata || {}).merge("slack_channel" => result["channel"])) if result["channel"]
    else
      notification.mark_failed!(result["error"] || "slack_error")
    end
  rescue SlackOauthClient::SlackApiError => e
    notification.mark_failed!(e.message)
    raise
  end

  # "not_in_channel" means the bot has never been added to the target
  # channel. Rather than fail every delivery until a human runs /invite in
  # Slack, try to self-heal by joining the (public) channel and posting
  # again once. Only ever improves the outcome — if the join itself fails
  # (private channel, or the workspace's token predates the channels:join
  # scope), the original not_in_channel result is what gets reported.
  def retry_after_joining(bot_token, channel, notification)
    join_result = SlackOauthClient.join_channel(bot_token: bot_token, channel: channel)
    return { "ok" => false, "error" => "not_in_channel" } unless join_result["ok"]

    SlackOauthClient.post_message(bot_token: bot_token, channel: channel, text: slack_text(notification), blocks: slack_blocks(notification))
  rescue SlackOauthClient::SlackApiError
    { "ok" => false, "error" => "not_in_channel" }
  end

  def slack_text(notification)
    "*#{notification.title}*\n#{notification.message}"
  end

  # Rich layout for advanced incidents only; nil keeps every other alert's
  # Slack message exactly as before.
  def slack_blocks(notification)
    SlackIncidentMessageBuilder.new(notification).blocks
  end
end
