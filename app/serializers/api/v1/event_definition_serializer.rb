module Api
  module V1
    class EventDefinitionSerializer
      def initialize(event_definition)
        @event_definition = event_definition
      end

      def as_json(*)
        {
          id: @event_definition.id,
          name: @event_definition.name,
          group: @event_definition.group,
          type: @event_definition.event_type,
          created_at: @event_definition.created_at,
          updated_at: @event_definition.updated_at
        }
      end
    end
  end
end
