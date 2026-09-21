module Api
  module V1
    class EventsController < BaseController
      before_action :set_event_definition, only: %i[show update destroy]

      def index
        pagy, event_definitions = pagy(EventDefinition.order(created_at: :desc))
        response.headers.merge!(pagy_headers_merge(pagy))
        render json: event_definitions.map { |e| EventDefinitionSerializer.new(e).as_json }
      end

      def show
        render json: EventDefinitionSerializer.new(@event_definition).as_json
      end

      def create
        event_definition = EventDefinition.new(event_definition_params)
        event_definition.save!
        render json: EventDefinitionSerializer.new(event_definition).as_json, status: :created
      end

      def update
        @event_definition.update!(event_definition_params)
        render json: EventDefinitionSerializer.new(@event_definition).as_json
      end

      def destroy
        @event_definition.destroy!
        head :no_content
      end

      private

      def set_event_definition
        @event_definition = EventDefinition.find(params[:id])
      end

      # Public API field is "type"; remapped to the event_type column since
      # "type" is a reserved Active Record column name (single table
      # inheritance discriminator).
      def event_definition_params
        permitted = params.require(:event).permit(:name, :group, :type)
        permitted[:event_type] = permitted.delete(:type) if permitted.key?(:type)
        permitted
      end
    end
  end
end
