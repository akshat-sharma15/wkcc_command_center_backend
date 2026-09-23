module Api
  module V1
    class NotificationSerializer
      def initialize(notification)
        @notification = notification
      end

      def as_json(*)
        {
          id: @notification.id,
          alert_id: @notification.alert_id,
          channel: @notification.channel,
          status: @notification.status,
          title: @notification.title,
          message: @notification.message,
          metadata: @notification.metadata,
          read: @notification.read?,
          read_at: @notification.read_at,
          delivered_at: @notification.delivered_at,
          created_at: @notification.created_at
        }
      end
    end
  end
end
