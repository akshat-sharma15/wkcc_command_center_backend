module Api
  module V1
    class AlertSerializer
      def initialize(alert)
        @alert = alert
      end

      def as_json(*)
        {
          id: @alert.id,
          name: @alert.name,
          role: @alert.role,
          description: @alert.description,
          event: {
            id: @alert.event_definition_id,
            name: @alert.event_definition.name,
            group: @alert.event_definition.group,
            type: @alert.event_definition.event_type
          },
          created_at: @alert.created_at,
          updated_at: @alert.updated_at
        }
      end
    end
  end
end
