# Fleet Monitoring POC vehicle listing - additive, isolated from the
# existing Api::V1::VehiclesController (which continues to serve the full
# ~325-vehicle Command Center dataset unchanged). Only the ~100 vehicles
# flagged `fleet_monitoring_poc: true` are exposed here (see
# db/seeds/fleet_monitoring_poc.rb).
module Api
  module V1
    module FleetMonitoring
      class VehiclesController < Api::V1::BaseController
        # EMERGENCY PERF FIX (see PERFORMANCE.md): pass `?summary=true` for
        # the map's default view (all ~200 vehicles as markers) to skip
        # ETA/route computation for every vehicle. Default is unchanged
        # (full payload) so no existing caller breaks; the frontend opts
        # in per the "markers only unless a vehicle/incident is selected"
        # spec.
        def index
          vehicles = Vehicle.fleet_monitoring_poc
                             .includes(:current_geo_location, :vendor_account, :driver, hub: :geo_location)
                             .order(:number)

          vehicles = vehicles.where(current_geo_location: { city: params[:city] }) if params[:city].present?
          vehicles = vehicles.where(current_geo_location: { state: params[:state] }) if params[:state].present?
          vehicles = filter_by_vendor(vehicles, params[:vendor]) if params[:vendor].present?

          vehicles = vehicles.to_a
          context = ::FleetMonitoring::VehicleBatchContext.new(vehicles)
          summary = ActiveModel::Type::Boolean.new.cast(params[:summary])
          presented = vehicles.map { |v| ::FleetMonitoring::VehiclePresenter.new(v, context: context, summary: summary).as_json }
          if params[:status].present?
            wanted = params[:status].to_s.upcase.tr("_", " ")
            presented = presented.select { |v| v[:status] == wanted }
          end

          render json: presented
        end

        # GET /api/v1/fleet-monitoring/vehicles/:pnr - truck detail: the
        # list shape plus ETA/route detail, waybills and open incidents.
        def show
          vehicle = Vehicle.fleet_monitoring_poc.includes(:current_geo_location, :vendor_account, :driver, hub: :geo_location)
                           .find_by!(number: params[:pnr])
          presenter = ::FleetMonitoring::VehiclePresenter.new(vehicle)
          trip = ::FleetMonitoring::VehiclePresenter.current_trip_for(vehicle)
          render json: presenter.as_json.merge(
            eta_detail: trip && EtaImpactService.new(trip, vehicle: vehicle).as_json,
            waybills: (trip ? trip.waybills.includes(:vehicle, :origin_hub, :destination_hub).order(:waybill_number) : Waybill.none)
                        .map { |w| Api::V1::WaybillSerializer.new(w).as_json }
          )
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
