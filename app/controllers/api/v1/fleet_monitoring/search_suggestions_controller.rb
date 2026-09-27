# Fleet Monitoring search autocomplete - a dedicated lightweight endpoint,
# separate from SearchController's full vehicle/package detail lookups.
# The frontend resolves a chosen suggestion through those existing
# endpoints/data, so this only returns what's needed to render the list.
# See FleetMonitoring::SearchSuggestions.
module Api
  module V1
    module FleetMonitoring
      class SearchSuggestionsController < Api::V1::BaseController
        rescue_from ::FleetMonitoring::SearchSuggestions::QueryTooShort, with: :render_bad_request

        # GET /api/v1/fleet-monitoring/search/suggestions?q=VH-0&limit=5
        def index
          params.require(:q)
          render json: ::FleetMonitoring::SearchSuggestions.new(params[:q], limit: params[:limit]).as_json
        end
      end
    end
  end
end
