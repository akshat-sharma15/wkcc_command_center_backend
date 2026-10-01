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

  # The shared incident card (IncidentNotificationPresenter) - the same
  # content Slack renders - so the browser needs no extra fetch.
  def self.incident_summary(notification)
    notification.alert && IncidentNotificationPresenter.new(notification.alert).as_json
  end

  # Pushes an alert's new status/assignment to every user who received a
  # notification for it (event "incident_update" on the existing stream).
  def self.publish_incident_update(alert)
    card = IncidentNotificationPresenter.new(alert).as_json
    payload = {
      event: "incident_update", alert_id: alert.id, status: alert.status,
      severity: alert.severity, incident: card, updated_at: alert.updated_at.iso8601
    }.to_json
    redis = Redis.new(url: redis_url)
    alert.notifications.distinct.pluck(:recipient_user_id).each { |user_id| redis.publish(channel_for(user_id), payload) }
  ensure
    redis&.close
  end

  def self.publish(notification)
    redis = Redis.new(url: redis_url)
    payload = {
      id: notification.id,
      alert_id: notification.alert_id,
      title: notification.title,
      message: notification.message,
      metadata: notification.metadata,
      severity: notification.metadata&.dig("severity"),
      incident: incident_summary(notification),
      deep_link: incident_summary(notification)&.dig(:links, :incident) || IncidentLinks.notification(notification.id),
      created_at: notification.created_at.iso8601
    }.to_json
    redis.publish(channel_for(notification.recipient_user_id), payload)
  ensure
    redis&.close
  end
end
