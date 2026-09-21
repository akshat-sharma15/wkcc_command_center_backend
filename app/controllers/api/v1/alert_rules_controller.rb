module Api
  module V1
    class AlertRulesController < BaseController
      before_action :set_alert_rule, only: %i[show update destroy]

      def index
        pagy, alert_rules = pagy(AlertRule.order(created_at: :desc))
        response.headers.merge!(pagy_headers_merge(pagy))
        render json: alert_rules.map { |r| AlertRuleSerializer.new(r).as_json }
      end

      def show
        render json: AlertRuleSerializer.new(@alert_rule).as_json
      end

      def create
        alert_rule = AlertRule.new(alert_rule_params)
        alert_rule.save!
        render json: AlertRuleSerializer.new(alert_rule).as_json, status: :created
      end

      def update
        @alert_rule.update!(alert_rule_params)
        render json: AlertRuleSerializer.new(@alert_rule).as_json
      end

      def destroy
        @alert_rule.destroy!
        head :no_content
      end

      private

      def set_alert_rule
        @alert_rule = AlertRule.find(params[:id])
      end

      # Every field here still goes through AlertRule's own validations
      # (group/field/operator/severity/recipient/channels) — this is just
      # the strong-params boundary, never the trust boundary.
      def alert_rule_params
        params.require(:alert_rule).permit(
          :name, :group, :field, :operator, :value, :severity, :notify,
          :recipient_type, :recipient_id, :enabled, :event_definition_id,
          notification_channels: []
        )
      end
    end
  end
end
