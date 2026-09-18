# Bearer-token authentication for service-to-service API access. Every
# controller under Api::V1 includes this via Api::V1::BaseController.
module ApiAuthenticatable
  extend ActiveSupport::Concern

  included do
    attr_reader :current_api_client
  end

  def authenticate_api_client!
    token = bearer_token_from_header
    @current_api_client = ApiClient.authenticate(token)

    if current_api_client
      current_api_client.update_column(:last_used_at, Time.current)
    else
      render json: { error: "Unauthorized" }, status: :unauthorized
    end
  end

  def require_scope!(scope)
    return if current_api_client&.has_scope?(scope)

    render json: { error: "Forbidden" }, status: :forbidden
  end

  private

  def bearer_token_from_header
    auth_header = request.headers["Authorization"]
    return nil if auth_header.blank?

    scheme, token = auth_header.split(" ", 2)
    return nil unless scheme&.casecmp("Bearer")&.zero?

    token
  end
end
