module Api
  module V1
    # Alert (occurrence) history + lifecycle actions. Alerts are never
    # deleted - resolve is the terminal action. Lifecycle actions record
    # the acting Superset user (X-Superset-User-Id, see
    # SupersetUserIdentifiable); read endpoints don't require it.
    class AlertsController < BaseController
      include SupersetUserIdentifiable

      rescue_from Alert::TransitionError, with: :render_transition_error

      before_action :set_alert, except: :index

      # GET /api/v1/alerts?status=open&severity=critical&incident_key=route.diversion
      def index
        scope = Alert.includes(:alert_rule).order(triggered_at: :desc)
        scope = scope.where(status: params[:status]) if params[:status].present?
        scope = scope.where(severity: params[:severity]) if params[:severity].present?
        scope = scope.where("alerts.metadata -> 'incident' ->> 'key' = ?", params[:incident_key]) if params[:incident_key].present?
        pagy, alerts = pagy(scope)
        response.headers.merge!(pagy_headers_merge(pagy))
        render json: alerts.map { |alert| AlertSerializer.new(alert).as_json }
      end

      def show
        render_alert
      end

      # POST /api/v1/alerts/:id/acknowledge
      def acknowledge
        @alert.acknowledge!(by: current_superset_user_id)
        notify_lifecycle("acknowledged")
        render_alert
      end

      # POST /api/v1/alerts/:id/assign   { assignee_type, assignee_id }
      # POST /api/v1/alerts/:id/reassign (same body)
      def assign
        params.require(:assignee_type)
        params.require(:assignee_id)
        validate_assignee!
        previous_assignee = @alert.assignee
        @alert.assign!(assignee_type: params[:assignee_type], assignee_id: params[:assignee_id], by: current_superset_user_id)
        notify_lifecycle(previous_assignee ? "reassigned" : "assigned", previous_assignee: previous_assignee)
        render_alert
      end

      def reassign
        raise Alert::TransitionError, "the alert has no assignee yet - use assign" unless @alert.assignee

        assign
      end

      # POST /api/v1/alerts/:id/escalate
      def escalate
        previous_assignee = @alert.assignee
        @alert.escalate!(by: current_superset_user_id)
        notify_lifecycle("escalated", previous_assignee: previous_assignee)
        render_alert
      end

      # POST /api/v1/alerts/:id/resolve   { resolution_note }
      def resolve
        @alert.resolve!(by: current_superset_user_id, note: params[:resolution_note])
        RouteDiversion.active.where(alert_id: @alert.id).find_each(&:resolve!) if params[:resolve_diversion].to_s == "true"
        notify_lifecycle("resolved")
        render_alert
      end

      private

      def set_alert
        @alert = Alert.includes(:alert_rule).find(params[:id])
      end

      # After a lifecycle action: push the new state to connected users
      # (existing SSE stream) and re-render the Slack messages, then respond.
      def render_alert
        broadcast_update if request.post?
        render json: AlertSerializer.new(@alert).as_json
      end

      def broadcast_update
        RealtimeNotificationPublisher.publish_incident_update(@alert)
        SlackIncidentSyncJob.perform_async(@alert.id)
      rescue Redis::BaseError => e
        Rails.logger.warn("[AlertsController] incident update not broadcast: #{e.class}")
      end

      # Notifies the people the action affects who would otherwise hear
      # nothing - above all a newly assigned user, who has no Notification
      # for this alert yet and so is reached by neither the SSE incident
      # update nor the Slack message re-render. Never fails the action
      # itself: the lifecycle transition is already committed.
      def notify_lifecycle(action, previous_assignee: nil)
        IncidentLifecycleNotifier.notify(@alert, action: action, actor_id: current_superset_user_id,
                                                 previous_assignee: previous_assignee)
      rescue StandardError => e
        Rails.logger.warn("[AlertsController] lifecycle notification failed: #{e.class}: #{e.message}")
      end

      def validate_assignee!
        return unless SupersetDirectory.configured?
        return if SupersetDirectory.resolve_principal(params[:assignee_type], params[:assignee_id])

        raise Alert::TransitionError, "assignee does not exist in Superset"
      end

      def render_transition_error(exception)
        render json: { error: exception.message }, status: :unprocessable_content
      end
    end
  end
end
