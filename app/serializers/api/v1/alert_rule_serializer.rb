module Api
  module V1
    class AlertRuleSerializer
      def initialize(alert_rule)
        @alert_rule = alert_rule
      end

      def as_json(*)
        {
          id: @alert_rule.id,
          name: @alert_rule.name,
          trigger_type: @alert_rule.trigger_type,
          group: @alert_rule.group,
          group_label: @alert_rule.group&.titleize,
          field: @alert_rule.field,
          field_label: @alert_rule.field&.titleize,
          operator: @alert_rule.operator,
          value: @alert_rule.value,
          severity: @alert_rule.severity,
          notify: @alert_rule.notify,
          event_definition_id: @alert_rule.event_definition_id,
          event_definition_name: @alert_rule.event_definition&.name,
          recipient_type: @alert_rule.recipient_type,
          recipient_id: @alert_rule.recipient_id,
          recipient_name: recipient_name,
          notification_channels: @alert_rule.notification_channels,
          enabled: @alert_rule.enabled,
          created_at: @alert_rule.created_at,
          updated_at: @alert_rule.updated_at
        }
      end

      private

      # nil whenever there's no recipient, Superset isn't configured, or
      # the recipient_id doesn't resolve — never raises just to render a
      # list.
      def recipient_name
        return nil if @alert_rule.recipient_type.blank? || @alert_rule.recipient_id.blank?

        found = case @alert_rule.recipient_type
        when "role" then SupersetDirectory.find_role(@alert_rule.recipient_id)
        when "user" then SupersetDirectory.find_user(@alert_rule.recipient_id)
        end
        found&.fetch(:name, nil)
      end
    end
  end
end
