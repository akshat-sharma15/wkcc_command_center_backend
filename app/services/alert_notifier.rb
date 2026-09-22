# Fans an Alert out into Notification rows + delivery jobs. The single
# place both trigger pipelines (AlertEvaluationJob for condition rules,
# EventPublisher for event rules) call once an Alert exists — neither
# duplicates this logic.
class AlertNotifier
  def self.notify(alert, rule)
    return unless rule.notify?

    user_ids = AlertRecipientResolver.new(rule).user_ids
    return if user_ids.empty?

    builder = AlertNotificationMessageBuilder.new(alert)
    channels = rule.notification_channels & Notification::CHANNELS

    user_ids.each do |user_id|
      channels.each do |channel|
        notification = Notification.create!(
          alert: alert,
          recipient_user_id: user_id,
          channel: channel,
          status: "pending",
          title: builder.title,
          message: builder.message,
          metadata: builder.metadata
        )
        NotificationDeliveryJob.perform_async(notification.id)
      end
    end
  end
end
