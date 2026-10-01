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

      # Package-centric on purpose (identifier/status/promised_delivery_at
      # are Package's own columns, not Order's) - we don't surface Orders
      # in the waybill UI. `total_orders`/`customer_count` stay on
      # WaybillSerializer's own top-level shape (the document's own
      # consignee-count summary, not a per-package Order listing).
      def show
        waybill = Waybill.find(params[:id])
        render json: WaybillSerializer.new(waybill).as_json.merge(
          packages: waybill.packages.order(:identifier).map { |package|
            { identifier: package.identifier, status: package.status, promised_delivery_at: package.promised_delivery_at }
          }
        )
      end
    end
  end
end
