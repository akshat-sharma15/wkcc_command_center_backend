# Fleet Monitoring hub listing - additive, isolated from the existing
# Api::V1::HubsController. Exposes all real hubs (the hub network is
# already small/real and every hub is part of the POC's route scenarios),
# each enriched with a resolved Location (lat/lng). Hubs are not
# associated with a Vendor - only vehicles are.
module Api
  module V1
    module FleetMonitoring
      class HubsController < Api::V1::BaseController
        def index
          hubs = Hub.includes(:geo_location).order(:code)
          flow = ::FleetMonitoring::HubVehicleFlow.counts_by_hub
          render json: hubs.map { |h| ::FleetMonitoring::HubPresenter.new(h, flow_counts: flow.fetch(h.id, { inbound: 0, outbound: 0 })).as_json }
        end
      end
    end
  end
end
