module Api
  module V1
    class WarehousesController < BaseController
      before_action :set_warehouse, only: %i[show update destroy]

      def index
        pagy, warehouses = pagy(Warehouse.order(created_at: :desc))
        response.headers.merge!(pagy_headers_merge(pagy))
        render json: warehouses.map { |w| WarehouseSerializer.new(w).as_json }
      end

      def show
        render json: WarehouseSerializer.new(@warehouse).as_json
      end

      def create
        warehouse = Warehouse.new(warehouse_params)
        warehouse.save!
        render json: WarehouseSerializer.new(warehouse).as_json, status: :created
      end

      def update
        @warehouse.update!(warehouse_params)
        render json: WarehouseSerializer.new(@warehouse).as_json
      end

      def destroy
        @warehouse.destroy!
        head :no_content
      end

      private

      def set_warehouse
        @warehouse = Warehouse.find(params[:id])
      end

      def warehouse_params
        params.require(:warehouse).permit(:name, :code, :location, :capacity, :status)
      end
    end
  end
end
