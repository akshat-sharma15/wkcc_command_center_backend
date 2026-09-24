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
    end
  end
end
