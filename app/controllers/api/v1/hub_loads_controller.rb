module Api
  module V1
    class HubLoadsController < BaseController
      # GET /api/v1/hubs/:hub_id/load?cutoff=2026-09-29T18:00:00Z
      def show
        hub = Hub.includes(:geo_location).find(params[:hub_id])
        cutoff = params[:cutoff].present? ? Time.zone.parse(params[:cutoff]) : nil
        render json: HubLoadService.new(hub, cutoff: cutoff).as_json
      end
    end
  end
end
