module Api
  module V1
    # Read-only recipient lookup, backed entirely by SupersetDirectory —
    # never queries Superset directly, never writes to it. Returns [] when
    # Superset isn't configured (the current state of this repository)
    # rather than erroring, since an empty recipient list is a safe
    # default for the Alert Builder frontend to render.
    class AlertRecipientsController < BaseController
      # GET /api/v1/alert-recipients/roles
      def roles
        render json: SupersetDirectory.roles
      end

      # GET /api/v1/alert-recipients/users
      def users
        render json: SupersetDirectory.users
      end
    end
  end
end
