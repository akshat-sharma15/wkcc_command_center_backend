module Api
  module V1
    class HubsController < BaseController
      before_action :set_hub, only: %i[show update destroy]

      def index
        pagy, hubs = pagy(Hub.order(created_at: :desc))
        response.headers.merge!(pagy_headers_merge(pagy))
        render json: hubs.map { |h| HubSerializer.new(h).as_json }
      end

      def show
        render json: HubSerializer.new(@hub).as_json
      end

      def create
        hub = Hub.new(hub_params)
        hub.save!
        render json: HubSerializer.new(hub).as_json, status: :created
      end

      def update
        @hub.update!(hub_params)
        render json: HubSerializer.new(@hub).as_json
      end

      def destroy
        @hub.destroy!
        head :no_content
      end

      private

      def set_hub
        @hub = Hub.find(params[:id])
      end

      def hub_params
        params.require(:hub).permit(
          :name, :code, :location, :capacity, :parking_capacity,
          :available_parking, :operational_status
        )
      end
    end
  end
end
