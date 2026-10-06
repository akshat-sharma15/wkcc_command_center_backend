module Api
  module V1
    # Plain REST endpoints only — the SSE stream itself lives in
    # NotificationsStreamController (ActionController::Live changes the
    # threading model for a controller and is kept isolated to the one
    # action that actually needs it).
    class NotificationsController < BaseController
      include SupersetUserIdentifiable

      before_action :set_notification, only: %i[show read]

      # GET /api/v1/notifications[?channel=in_app]
      def index
        pagy, notifications = pagy(channel_scope(Notification.includes(alert: :alert_rule).for_recipient(current_superset_user_id)).order(created_at: :desc))
        response.headers.merge!(pagy_headers_merge(pagy))
        render json: notifications.map { |n| NotificationSerializer.new(n).as_json }
      end

      # GET /api/v1/notifications/unread
      def unread
        notifications = channel_scope(Notification.includes(alert: :alert_rule).for_recipient(current_superset_user_id)).unread.order(created_at: :desc)
        render json: notifications.map { |n| NotificationSerializer.new(n).as_json }
      end

      # GET /api/v1/notifications/:id
      def show
        render json: NotificationSerializer.new(@notification).as_json
      end

      # PATCH /api/v1/notifications/:id/read
      def read
        @notification.mark_read!
        render json: NotificationSerializer.new(@notification).as_json
      end

      # GET /api/v1/notifications/sse-ticket
      #
      # A short-lived signed ticket for the SSE connection only (see
      # SupersetUserIdentifiable) — the stream endpoint itself can't be
      # authenticated via this header-based mechanism since EventSource
      # cannot send custom headers.
      POLL_LIMIT = 50
      INCIDENT_UPDATE_LIMIT = 20
      POLL_INTERVAL_SECONDS = 12

      # GET /api/v1/notifications/poll[?after_id=123&since=2026-10-06T10:00:00.000000Z]
      #
      # The in-app delivery transport (replaces the long-lived SSE stream):
      # a short, bounded read of persisted notifications that returns
      # immediately - it never waits for an event, so no request thread is
      # held between polls however many tabs/devices are open.
      #
      #   without after_id  bootstrap: the user's unread in-app notifications
      #                     (newest first) + the cursor to poll from
      #   with after_id     only notifications with id > after_id (oldest
      #                     first, POLL_LIMIT max; has_more when truncated)
      #   with since        incident cards of the user's alerts updated at
      #                     or after `since` (status/assignment changes)
      #
      # Always returns the authoritative unread_count and the next cursor.
      # `since` is the server time from the previous response, so client
      # clock skew never matters.
      def poll
        user_id = current_superset_user_id
        polled_at = Time.current
        scope = Notification.for_recipient(user_id).where(channel: "in_app")
        after_id = Integer(params[:after_id].to_s, exception: false)

        if after_id
          notifications = scope.where("notifications.id > ?", after_id).order(:id).limit(POLL_LIMIT).includes(alert: :alert_rule).to_a
          cursor = notifications.last&.id || after_id
        else
          # Cursor first, then the list bounded by it - a notification
          # created between the two queries is picked up by the next poll,
          # never skipped.
          cursor = scope.maximum(:id).to_i
          notifications = scope.unread.where("notifications.id <= ?", cursor).order(id: :desc)
                               .limit(POLL_LIMIT).includes(alert: :alert_rule).to_a
        end

        render json: {
          notifications: notifications.map { |n| NotificationSerializer.new(n).as_json },
          incident_updates: incident_updates(scope, params[:since]),
          unread_count: scope.unread.count,
          has_more: after_id.present? && notifications.size == POLL_LIMIT,
          cursor: { after_id: cursor, since: polled_at.utc.iso8601(6) },
          poll_interval_seconds: POLL_INTERVAL_SECONDS
        }
      end

      def sse_ticket
        render json: {
          ticket: issue_sse_ticket(current_superset_user_id),
          expires_in: SupersetUserIdentifiable::SSE_TICKET_TTL.to_i
        }
      end

      private

      # Optional ?channel= filter (the bell asks for in_app only; Slack
      # rows are that channel's delivery records for the same alert).
      # Live incident cards for this user's alerts changed since the last
      # poll (what the SSE "incident_update" event used to carry).
      def incident_updates(scope, since)
        time = since.present? ? (Time.zone.parse(since.to_s) rescue nil) : nil
        return [] unless time

        Alert.includes(:alert_rule).where(id: scope.select(:alert_id)).where("alerts.updated_at >= ?", time)
             .order(updated_at: :desc).limit(INCIDENT_UPDATE_LIMIT)
             .filter_map do |alert|
               card = IncidentNotificationPresenter.new(alert).as_json
               card && { alert_id: alert.id, status: alert.status, incident: card }
             end
      end

      def channel_scope(scope)
        Notification::CHANNELS.include?(params[:channel]) ? scope.where(channel: params[:channel]) : scope
      end

      # Scoped to the current user in the lookup itself (not filtered
      # after the fact) — an id belonging to another user's notification
      # simply 404s, never leaks whether it exists.
      def set_notification
        @notification = Notification.for_recipient(current_superset_user_id).find(params[:id])
      end
    end
  end
end
