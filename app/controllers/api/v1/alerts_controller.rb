module Api
  module V1
    class AlertsController < BaseController
      before_action :set_alert, only: %i[show update destroy]

      def index
        pagy, alerts = pagy(Alert.order(created_at: :desc))
        response.headers.merge!(pagy_headers_merge(pagy))
        render json: alerts.map { |a| AlertSerializer.new(a).as_json }
      end

      def show
        render json: AlertSerializer.new(@alert).as_json
      end

      def create
        alert = Alert.new(alert_params)
        alert.save!
        render json: AlertSerializer.new(alert).as_json, status: :created
      end

      def update
        @alert.update!(alert_params)
        render json: AlertSerializer.new(@alert).as_json
      end

      def destroy
        @alert.destroy!
        head :no_content
      end

      private

      def set_alert
        @alert = Alert.find(params[:id])
      end

      # Public API field is "event" (an event definition id); remapped to
      # the event_definition_id foreign key.
      def alert_params
        permitted = params.require(:alert).permit(:name, :event_id, :role, :description)
        permitted[:event_definition_id] = permitted.delete(:event_id) if permitted.key?(:event_id)
        permitted
      end
    end
  end
end
