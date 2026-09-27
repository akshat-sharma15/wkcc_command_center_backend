# Fleet Monitoring POC vehicle listing - additive, isolated from the
# existing Api::V1::VehiclesController (which continues to serve the full
# ~325-vehicle Command Center dataset unchanged). Only the ~100 vehicles
# flagged `fleet_monitoring_poc: true` are exposed here (see
# db/seeds/fleet_monitoring_poc.rb).
module Api
  module V1
    module FleetMonitoring
      class VehiclesController < Api::V1::BaseController
        def index
          vehicles = Vehicle.fleet_monitoring_poc
                             .includes(:current_geo_location, :vendor_account, :driver)
                             .order(:number)

          vehicles = vehicles.where(current_geo_location: { city: params[:city] }) if params[:city].present?
          vehicles = vehicles.where(current_geo_location: { state: params[:state] }) if params[:state].present?
          vehicles = filter_by_vendor(vehicles, params[:vendor]) if params[:vendor].present?

          presented = vehicles.map { |v| ::FleetMonitoring::VehiclePresenter.new(v).as_json }
          if params[:status].present?
            wanted = params[:status].to_s.upcase.tr("_", " ")
            presented = presented.select { |v| v[:status] == wanted }
          end

          render json: presented
        end

        private

        def filter_by_vendor(scope, vendor)
          scope.left_joins(:vendor_account)
               .where("vendors.name = :v OR vehicles.vendor = :v", v: vendor)
        end
      end
    end
  end
end
