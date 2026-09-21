module Api
  module V1
    # Deliberately whitelist-only: lists exactly the fields exposed, never
    # `as_json` on the model or any field-exclusion approach, so a new
    # sensitive column added later doesn't leak by default.
    class IntegrationSerializer
      def initialize(integration)
        @integration = integration
      end

      def as_json(*)
        {
          id: @integration.id,
          type: @integration.provider,
          status: @integration.status,
          enabled: @integration.enabled,
          workspace: {
            id: @integration.workspace_id,
            name: @integration.workspace_name
          }
        }
      end
    end
  end
end
