# Fleet Monitoring search - a dedicated endpoint, deliberately separate
# from VehiclesController#index (see task section 12: "Search MUST be a
# separate API"). `pnr` resolves against Vehicle#number: the current
# truck_monitoring frontend's "pnr" concept is the vehicle's own
# identifier, not a distinct trip tracking number (trips have no such
# field), confirmed by reading data.js/app.js directly rather than
# assuming the older brief's premise still holds.
module Api
  module V1
    module FleetMonitoring
      class SearchController < Api::V1::BaseController
        # GET /api/v1/fleet-monitoring/search?pnr=VH-0001
        def vehicle
          params.require(:pnr)
          vehicle = Vehicle.fleet_monitoring_poc.find_by!(number: params[:pnr])
          render json: ::FleetMonitoring::VehiclePresenter.new(vehicle).as_json
        end

        # GET /api/v1/fleet-monitoring/search/package?package_id=KWS4567
        def package
          params.require(:package_id)
          package = Package.find_by!(identifier: params[:package_id])
          render json: ::FleetMonitoring::PackagePresenter.new(package).as_json
        end
      end
    end
  end
end
