module Api
  module V1
    class AlertSerializer
      def initialize(alert)
        @alert = alert
      end

      def as_json(*)
        rule = @alert.alert_rule
        {
          id: @alert.id,
          alert_rule_id: @alert.alert_rule_id,
          rule_name: rule&.name,
          trigger_type: rule&.trigger_type,
          group: @alert.group,
          record_id: @alert.record_id,
          field: @alert.field,
          expected_value: @alert.expected_value,
          actual_value: @alert.actual_value,
          severity: @alert.severity,
          status: @alert.status,
          triggered_at: @alert.triggered_at,
          incident: @alert.metadata&.dig("incident"),
          # The same compact card Slack and the notification bell render.
          card: IncidentNotificationPresenter.new(@alert).as_json,
          assignee: principal(@alert.assignee_type, @alert.assignee_id),
          assignment_level: @alert.assignment_level,
          assigned_at: @alert.assigned_at,
          primary_assignee: rule && principal(rule.primary_assignee_type, rule.primary_assignee_id),
          secondary_assignee: rule && principal(rule.secondary_assignee_type, rule.secondary_assignee_id),
          escalation_level: @alert.escalation_level,
          escalation_due_at: @alert.escalation_due_at,
          escalated_at: @alert.escalated_at,
          escalated_by: @alert.escalated_by,
          acknowledged_at: @alert.acknowledged_at,
          acknowledged_by: @alert.acknowledged_by,
          resolved_at: @alert.resolved_at,
          resolved_by: @alert.resolved_by,
          resolution_note: @alert.resolution_note,
          history: Array(@alert.metadata&.dig("history")).map { |entry| with_names(entry) },
          metadata: @alert.metadata&.except("incident", "history"),
          created_at: @alert.created_at,
          updated_at: @alert.updated_at
        }
      end

      private

      # History entries store logical ids; add display names for the UI.
      def with_names(entry)
        entry.merge(
          "actor_name" => entry["actor_id"] && SupersetDirectory.resolve_principal("user", entry["actor_id"])&.fetch(:name, nil),
          "from_name" => entry["from"] && SupersetDirectory.resolve_principal(entry["from"]["type"], entry["from"]["id"])&.fetch(:name, nil),
          "to_name" => entry["to"] && SupersetDirectory.resolve_principal(entry["to"]["type"], entry["to"]["id"])&.fetch(:name, nil)
        ).compact
      end

      def principal(type, id)
        return nil if type.blank? || id.blank?

        { type: type, id: id, name: SupersetDirectory.resolve_principal(type, id)&.fetch(:name, nil) }
      end
    end
  end
end
