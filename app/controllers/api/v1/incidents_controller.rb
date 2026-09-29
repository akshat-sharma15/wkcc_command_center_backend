module Api
  module V1
    # Front door for publishing the advanced incidents by stable key (see
    # IncidentCatalog / IncidentPublisher). Route diversions are published
    # by RouteDiversionsController#create instead, since they first need
    # a persisted RouteDiversion to describe.
    class IncidentsController < BaseController
      rescue_from IncidentPublisher::UnknownIncident, with: :render_unknown

      # GET /api/v1/incidents - the catalog with each key's EventDefinition id.
      def index
        render json: IncidentCatalog::DEFINITIONS.map { |key, attrs|
          { key: key, event_definition_id: IncidentCatalog.event_definition(key)&.id }.merge(attrs)
        }
      end

      # POST /api/v1/incidents/:key   { entity_id, payload: {...} }
      def create
        key = params[:key]
        raise IncidentPublisher::UnknownIncident, "unknown incident '#{key}'" unless IncidentCatalog.advanced?(key)
        raise IncidentPublisher::UnknownIncident, "publish #{key} via POST /api/v1/route-diversions" if key == IncidentCatalog::ROUTE_DIVERSION

        entity_id = params.require(:entity_id)
        entity_model = key == IncidentCatalog::VEHICLE_FAILURE ? Vehicle : Hub
        entity_model.find(entity_id)

        alerts = IncidentPublisher.publish(key, entity_id: entity_id.to_i, payload: payload_params)
        render json: { alerts: alerts.map { |alert| AlertSerializer.new(alert.reload).as_json } }, status: :created
      end

      private

      def payload_params
        params.fetch(:payload, {}).permit!.to_h
      end

      def render_unknown(exception)
        render json: { error: exception.message }, status: :unprocessable_content
      end
    end
  end
end
