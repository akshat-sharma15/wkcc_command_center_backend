module Api
  module V1
    # Plain REST endpoints only — the SSE stream itself lives in
    # NotificationsStreamController (ActionController::Live changes the
    # threading model for a controller and is kept isolated to the one
    # action that actually needs it).
    class NotificationsController < BaseController
      include SupersetUserIdentifiable

      before_action :set_notification, only: %i[show read]

      # GET /api/v1/notifications
      def index
        pagy, notifications = pagy(Notification.for_recipient(current_superset_user_id).order(created_at: :desc))
        response.headers.merge!(pagy_headers_merge(pagy))
        render json: notifications.map { |n| NotificationSerializer.new(n).as_json }
      end

      # GET /api/v1/notifications/unread
      def unread
        notifications = Notification.for_recipient(current_superset_user_id).unread.order(created_at: :desc)
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
      def sse_ticket
        render json: {
          ticket: issue_sse_ticket(current_superset_user_id),
          expires_in: SupersetUserIdentifiable::SSE_TICKET_TTL.to_i
        }
      end

      private

      # Scoped to the current user in the lookup itself (not filtered
      # after the fact) — an id belonging to another user's notification
      # simply 404s, never leaks whether it exists.
      def set_notification
        @notification = Notification.for_recipient(current_superset_user_id).find(params[:id])
      end
    end
  end
end
