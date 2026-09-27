# Fleet Monitoring package listing - additive, isolated from the existing
# Api::V1::PackagesController. Scoped to "live/actionable" packages for the
# POC fleet: currently in transit on a POC vehicle, or still backlogged
# (pending/received, i.e. not yet dispatched or delivered) at a hub that
# POC vehicles operate out of - not the full historical package log, which
# would return most of the ~15k real packages regardless of POC scope.
module Api
  module V1
    module FleetMonitoring
      class PackagesController < Api::V1::BaseController
        def index
          poc_vehicle_ids = Vehicle.fleet_monitoring_poc.select(:id)
          in_transit_trip_ids = Trip.where(vehicle_id: poc_vehicle_ids, status: "in_transit").select(:id)
          poc_hub_ids = Vehicle.fleet_monitoring_poc.select(:hub_id)

          scope = Package.where(trip_id: in_transit_trip_ids)
                          .or(Package.where(location_type: "Hub", location_id: poc_hub_ids, status: %w[pending received]))
                          .order(created_at: :desc)

          pagy, packages = pagy(scope)
          response.headers.merge!(pagy_headers_merge(pagy))
          render json: packages.map { |p| ::FleetMonitoring::PackagePresenter.new(p).as_json }
        end
      end
    end
  end
end
