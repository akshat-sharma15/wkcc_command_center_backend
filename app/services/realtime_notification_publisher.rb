# Realtime fan-out only — Redis is never the durable notification store
# (that's the `notifications` table in operations; a Notification row
# always exists before this publishes). Uses REDIS_EVENTS_DB, reserved
# for exactly this purpose since Stage 1 (see ARCHITECTURE.md's Redis
# section) and unused until now.
#
# One pub/sub channel per recipient user id, so
# Api::V1::NotificationsController#stream only ever subscribes to the
# connected user's own channel — never a broadcast-to-everyone channel a
# client could listen in on.
class RealtimeNotificationPublisher
  def self.channel_for(user_id)
    "notifications:user:#{user_id}"
  end

  def self.redis_url
    ENV.fetch("REDIS_EVENTS_URL") do
      "redis://#{ENV.fetch('REDIS_HOST', 'localhost')}:#{ENV.fetch('REDIS_PORT', 6380)}/#{ENV.fetch('REDIS_EVENTS_DB', 6)}"
    end
  end

  def self.publish(notification)
    redis = Redis.new(url: redis_url)
    payload = {
      id: notification.id,
      alert_id: notification.alert_id,
      title: notification.title,
      message: notification.message,
      metadata: notification.metadata,
      created_at: notification.created_at.iso8601
    }.to_json
    redis.publish(channel_for(notification.recipient_user_id), payload)
  ensure
    redis&.close
  end
end
