# Keeps posted Slack incident messages in step with the Alert after a
# lifecycle action: re-renders each delivered Slack notification of the
# alert (SlackIncidentMessageBuilder reads the live Alert) via chat.update.
# Slack holds no incident state of its own - the Alert record is the only
# source of truth. Messages posted before the channel id was recorded
# are skipped (nothing to address them with).
class SlackIncidentSyncJob < ApplicationJob
  sidekiq_options retry: 3

  def perform(alert_id)
    alert = Alert.find_by(id: alert_id)
    integration = Integration.find_by(provider: "slack")
    return [] unless alert && integration&.connected? && integration.bot_token.present?

    results = []
    alert.notifications.where(channel: "slack", status: "delivered").where.not(external_reference: nil).find_each do |notification|
      channel = notification.metadata&.dig("slack_channel")
      next if channel.blank?

      blocks = SlackIncidentMessageBuilder.new(notification).blocks
      next unless blocks

      result = SlackOauthClient.update_message(bot_token: integration.bot_token, channel: channel, ts: notification.external_reference,
                                               text: "*#{notification.title}* — #{alert.status.upcase.tr('_', ' ')}", blocks: blocks)
      Rails.logger.warn("[SlackIncidentSyncJob] notification=#{notification.id} #{result['error']}") unless result["ok"]
      results << { notification_id: notification.id, ok: result["ok"], error: result["error"] }
    end
    results
  end
end
