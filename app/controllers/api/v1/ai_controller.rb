module Api
  module V1
    # Command Centre AI chatbot (Phase 5). Inherits BaseController's same
    # (currently disabled app-wide) bearer-token gate as every other
    # controller here - see BaseController's commented-out
    # `authenticate_api_client!` before_action. Re-enabling it protects
    # this endpoint exactly like the rest of the API, with no special
    # case needed.
    class AiController < BaseController
      # POST /api/v1/ai/chat
      def chat
        message = params.require(:message)
        result = CommandCenter::AiChatService.call(message: message, session_key: params[:conversation_id])

        render json: result, status: :ok
      rescue CommandCenter::AiChatService::ChatError => e
        render json: { error: e.message }, status: :unprocessable_content
      end

      # POST /api/v1/ai/chart_chat
      #
      # Chart-scoped chat. Unlike #chat this is NOT called by the browser:
      # Superset calls it after resolving a chart id to a chart + dataset
      # under the signed-in user's own permissions, and sends the resulting
      # context here (see superset/chart_chat/api.py). The context therefore
      # has to be trusted to have been built post-authorisation, which is
      # what the service token establishes - without it, a browser could
      # name any dataset it liked and read data the user cannot see.
      #
      # `message` is optional: omitting it opens the session and returns the
      # chart's summary.
      def chart_chat
        return render_forbidden unless valid_service_token?

        scope = CommandCenter::ChartScope.new(params.require(:context).permit!.to_h)
        return render json: { error: "context.chart.id is required" }, status: :bad_request if scope.chart_id.blank?

        result = CommandCenter::AiChatService.call(
          message: params[:message],
          session_key: params[:conversation_id],
          chart_scope: scope
        )

        render json: result, status: :ok
      rescue CommandCenter::AiChatService::ChatError => e
        render json: { error: e.message }, status: :unprocessable_content
      end

      private

      # Rejects the request unless the caller presents the shared secret.
      # Configuring no token at all leaves the endpoint closed rather than
      # open, so a missing deployment step can't silently expose it.
      def valid_service_token?
        expected = ENV["COMMAND_CENTER_SERVICE_TOKEN"].to_s
        return false if expected.blank?

        provided = request.headers["X-Command-Center-Service-Token"].to_s
        provided.present? && ActiveSupport::SecurityUtils.secure_compare(provided, expected)
      end

      def render_forbidden
        render json: { error: "Not authorised for chart chat" }, status: :forbidden
      end
    end
  end
end
