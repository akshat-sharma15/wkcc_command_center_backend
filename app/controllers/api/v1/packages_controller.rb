module Api
  module V1
    class PackagesController < BaseController
      before_action :set_package, only: %i[show update destroy]

      def index
        pagy, packages = pagy(Package.order(created_at: :desc))
        response.headers.merge!(pagy_headers_merge(pagy))
        render json: packages.map { |p| PackageSerializer.new(p).as_json }
      end

      def show
        render json: PackageSerializer.new(@package).as_json
      end

      def create
        package = Package.new(package_params)
        package.save!
        render json: PackageSerializer.new(package).as_json, status: :created
      end

      def update
        @package.update!(package_params)
        render json: PackageSerializer.new(@package).as_json
      end

      def destroy
        @package.destroy!
        head :no_content
      end

      private

      def set_package
        @package = Package.find(params[:id])
      end

      def package_params
        params.require(:package).permit(
          :identifier, :trip_id, :location_type, :location_id,
          :expected_quantity, :received_quantity, :damaged_quantity,
          :short_quantity, :status
        )
      end
    end
  end
end
