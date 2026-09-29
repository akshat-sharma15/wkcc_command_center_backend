# The shared incident card (IncidentNotificationPresenter) for the map's
# incident-context banner when it is opened from an alert link.
module Api
  module V1
    module FleetMonitoring
      class IncidentsController < Api::V1::BaseController
        # GET /api/v1/fleet-monitoring/incidents/:id
        def show
          card = IncidentNotificationPresenter.new(Alert.includes(:alert_rule).find(params[:id])).as_json
          return render json: { error: "not an advanced incident" }, status: :not_found unless card

          render json: card.except(:fields).merge(reason: Alert.find(params[:id]).metadata.dig("incident", "reason"))
        end
      end
    end
  end
end
