module Api
  module V1
    # Slack OAuth connect/status/disconnect only. Deliberately does NOT
    # implement message delivery, notification jobs, or anything that
    # actually uses the stored bot token beyond connecting/disconnecting —
    # that's a later phase.
    class SlackIntegrationsController < BaseController
      # GET /api/v1/integrations/slack
      def show
        integration = Integration.find_by(provider: "slack")
        if integration&.connected?
          render json: { connected: true, integration: IntegrationSerializer.new(integration).as_json }
        else
          render json: { connected: false }
        end
      end

      # GET /api/v1/integrations/slack/connect
      def connect
        unless SlackOauthClient.configured?
          return render json: { error: "Slack is not configured on this server" }, status: :service_unavailable
        end

        oauth_state = SlackOauthState.issue!
        render json: { authorization_url: SlackOauthClient.authorization_url(state: oauth_state.state) }
      end

      # GET /api/v1/integrations/slack/callback
      # Always redirects the browser back to the frontend — this endpoint
      # is hit by a real top-level navigation from Slack, not an XHR, so
      # there's no JSON response for a frontend caller to read directly.
      def callback
        return redirect_to_frontend(status: "error", reason: params[:error]) if params[:error].present?

        oauth_state = SlackOauthState.find_by(state: params[:state])
        if oauth_state.nil? || oauth_state.expired?
          return redirect_to_frontend(status: "error", reason: "invalid_state")
        end

        oauth_state.destroy! # one-time use, whether or not the exchange below succeeds

        result = SlackOauthClient.exchange_code(code: params[:code])
        return redirect_to_frontend(status: "error", reason: result["error"] || "oauth_failed") unless result["ok"]

        store_integration!(result)
        redirect_to_frontend(status: "success")
      rescue SlackOauthClient::SlackApiError
        redirect_to_frontend(status: "error", reason: "slack_unreachable")
      end

      # DELETE /api/v1/integrations/slack/:id
      def destroy
        integration = Integration.find(params[:id])
        SlackOauthClient.revoke_token(bot_token: integration.bot_token) if integration.bot_token.present?

        integration.update!(
          status: "disconnected",
          enabled: false,
          bot_token: nil,
          bot_user_id: nil,
          scope: nil
        )
        head :no_content
      end

      private

      # Reconnecting an already-connected workspace (or a previously
      # disconnected one) updates this single row rather than creating a
      # duplicate — there is one Integration per provider (see the
      # `provider` uniqueness constraint), matching the product surface of
      # "is Slack connected", not a history of connection attempts.
      def store_integration!(result)
        integration = Integration.find_or_initialize_by(provider: "slack")
        integration.update!(
          status: "connected",
          enabled: true,
          workspace_id: result.dig("team", "id"),
          workspace_name: result.dig("team", "name"),
          bot_user_id: result["bot_user_id"],
          scope: result["scope"],
          bot_token: result["access_token"]
        )
      end

      def redirect_to_frontend(status:, reason: nil)
        uri = URI.parse(ENV.fetch("FRONTEND_BASE_URL", "http://localhost:9000"))
        uri.path = "/integration/list/"
        query = { slack: status }
        query[:reason] = reason if reason
        uri.query = query.to_query
        redirect_to uri.to_s, allow_other_host: true
      end
    end
  end
end
