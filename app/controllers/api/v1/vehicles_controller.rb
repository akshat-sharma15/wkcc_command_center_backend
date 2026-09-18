module Api
  module V1
    class VehiclesController < BaseController
      before_action :set_vehicle, only: %i[show update destroy]

      def index
        pagy, vehicles = pagy(Vehicle.order(created_at: :desc))
        response.headers.merge!(pagy_headers_merge(pagy))
        render json: vehicles.map { |v| VehicleSerializer.new(v).as_json }
      end

      def show
        render json: VehicleSerializer.new(@vehicle).as_json
      end

      def create
        vehicle = Vehicle.new(vehicle_params)
        vehicle.save!
        render json: VehicleSerializer.new(vehicle).as_json, status: :created
      end

      def update
        @vehicle.update!(vehicle_params)
        render json: VehicleSerializer.new(@vehicle).as_json
      end

      def destroy
        @vehicle.destroy!
        head :no_content
      end

      private

      def set_vehicle
        @vehicle = Vehicle.find(params[:id])
      end

      def vehicle_params
        params.require(:vehicle).permit(
          :number, :vehicle_type, :status, :capacity, :vendor,
          :current_location, :hub_id, :driver_id
        )
      end
    end
  end
end
