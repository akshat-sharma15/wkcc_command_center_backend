module Api
  module V1
    # GET /api/v1/notifications/stream?ticket=...
    #
    # Kept as its own controller (not an action on NotificationsController)
    # since ActionController::Live changes the threading model for the
    # whole controller it's included in — isolating it here keeps that
    # blast radius to exactly the one streaming action.
    class NotificationsStreamController < BaseController
      include ActionController::Live
      include SupersetUserIdentifiable

      HEARTBEAT_INTERVAL = 20 # seconds

      def stream
        user_id = ticket_user_id
        return render_unidentified_user unless user_id

        response.headers["Content-Type"] = "text/event-stream"
        response.headers["Cache-Control"] = "no-cache"
        response.headers["X-Accel-Buffering"] = "no"

        write_sse(event: "connected", data: { user_id: user_id })
        subscribe_and_stream(user_id)
      rescue ActionController::Live::ClientDisconnected, IOError
        # The browser navigated away/closed the tab — normal, not an error.
      ensure
        response.stream.close
      end

      private

      def ticket_user_id
        payload = verify_sse_ticket(params[:ticket])
        payload && payload["user_id"]
      end

      # redis-rb's #subscribe_with_timeout returns (without unsubscribing
      # the connection) whenever no message arrives within `timeout` —
      # looping around it turns that into a periodic heartbeat tick, and
      # re-subscribing is cheap (no missed-message window worth guarding,
      # since the durable record is the `notifications` table, not this
      # stream — see RealtimeNotificationPublisher).
      def subscribe_and_stream(user_id)
        redis = Redis.new(url: RealtimeNotificationPublisher.redis_url)
        channel = RealtimeNotificationPublisher.channel_for(user_id)

        loop do
          message_received = false

          redis.subscribe_with_timeout(HEARTBEAT_INTERVAL, channel) do |on|
            on.message do |_channel, payload|
              message_received = true
              data = JSON.parse(payload)
              write_sse(event: "notification", id: data["id"], data: data)
            end
          end

          write_sse(comment: "heartbeat") unless message_received
        end
      ensure
        redis&.close
      end

      def write_sse(event: nil, id: nil, data: nil, comment: nil)
        if comment
          response.stream.write(": #{comment}\n\n")
          return
        end

        lines = []
        lines << "event: #{event}" if event
        lines << "id: #{id}" if id
        lines << "data: #{data.to_json}"
        response.stream.write("#{lines.join("\n")}\n\n")
      end
    end
  end
end
