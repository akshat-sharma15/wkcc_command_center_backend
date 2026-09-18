module Api
  module V1
    class TripsController < BaseController
      before_action :set_trip, only: %i[show update destroy]

      def index
        pagy, trips = pagy(Trip.order(created_at: :desc))
        response.headers.merge!(pagy_headers_merge(pagy))
        render json: trips.map { |t| TripSerializer.new(t).as_json }
      end

      def show
        render json: TripSerializer.new(@trip).as_json
      end

      def create
        trip = Trip.new(trip_params)
        trip.save!
        render json: TripSerializer.new(trip).as_json, status: :created
      end

      def update
        @trip.update!(trip_params)
        render json: TripSerializer.new(@trip).as_json
      end

      def destroy
        @trip.destroy!
        head :no_content
      end

      private

      def set_trip
        @trip = Trip.find(params[:id])
      end

      def trip_params
        params.require(:trip).permit(
          :vehicle_id, :origin_hub_id, :destination_hub_id, :departure_at,
          :expected_arrival_at, :actual_arrival_at, :status, :route_info
        )
      end
    end
  end
end
