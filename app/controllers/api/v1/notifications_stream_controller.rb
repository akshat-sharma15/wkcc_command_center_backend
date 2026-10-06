module Api
  module V1
    # GET /api/v1/notifications/stream - DEPRECATED.
    #
    # This used to be an infinite Server-Sent Events stream
    # (ActionController::Live + a Redis subscription). Each open browser tab
    # held one Puma request thread for the life of the connection, so ~10
    # open tabs exhausted the whole API thread pool and every endpoint
    # (including /up) stalled. In-app notifications are now delivered by
    # short, bounded polling of persisted notifications
    # (GET /api/v1/notifications/poll - see NotificationsController#poll),
    # and NotificationBell no longer opens an EventSource.
    #
    # The route is kept, not deleted, so a browser tab still running the old
    # frontend bundle gets an immediate, cheap answer instead of a 404 retry
    # loop: per the SSE spec, an EventSource receiving HTTP 204 stops
    # reconnecting. Nothing here waits, streams or touches Redis, and the
    # controller deliberately no longer includes ActionController::Live.
    # Once no deployed frontend references this URL, the route and this
    # controller (and the /sse-ticket endpoint) can be removed.
    class NotificationsStreamController < BaseController
      def stream
        response.headers["Cache-Control"] = "no-store"
        response.headers["Deprecation"] = "true"
        response.headers["Link"] = "</api/v1/notifications/poll>; rel=\"successor-version\""
        head :no_content
      end
    end
  end
end
