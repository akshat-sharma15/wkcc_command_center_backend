module Api
  module V1
    class WaybillsController < BaseController
      # GET /api/v1/waybills?vehicle_id=&vehicle_number=&trip_id=&status=
      def index
        scope = Waybill.includes(:vehicle, :origin_hub, :destination_hub).order(:waybill_number)
        scope = scope.where(vehicle_id: params[:vehicle_id]) if params[:vehicle_id].present?
        scope = scope.joins(:vehicle).where(vehicles: { number: params[:vehicle_number] }) if params[:vehicle_number].present?
        scope = scope.where(trip_id: params[:trip_id]) if params[:trip_id].present?
        scope = scope.where(status: params[:status]) if params[:status].present?
        pagy, waybills = pagy(scope)
        response.headers.merge!(pagy_headers_merge(pagy))
        render json: waybills.map { |w| WaybillSerializer.new(w).as_json }
      end

      def show
        waybill = Waybill.find(params[:id])
        render json: WaybillSerializer.new(waybill).as_json.merge(
          packages: waybill.packages.includes(:order).order(:identifier).map { |package|
            { identifier: package.identifier, status: package.status, order_number: package.order&.order_number,
              customer: package.order&.customer_reference, promised_delivery_at: package.order&.promised_delivery_at }
          }
        )
      end
    end
  end
end
