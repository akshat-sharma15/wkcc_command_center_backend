module Api
  module V1
    class BaseController < ApplicationController
      include ApiAuthenticatable
      include Pagy::Backend

      # Bearer-token enforcement is disabled for now (requested explicitly);
      # the ApiClient/ApiAuthenticatable mechanism is left in place so it can
      # be re-enabled by restoring this line.
      # before_action :authenticate_api_client!

      rescue_from ActiveRecord::RecordNotFound, with: :render_not_found
      rescue_from ActiveRecord::RecordInvalid, with: :render_unprocessable_content
      rescue_from ActiveRecord::RecordNotDestroyed, with: :render_unprocessable_content
      rescue_from ActionController::ParameterMissing, with: :render_bad_request
      rescue_from StandardError, with: :render_internal_error unless Rails.env.local?

      private

      def render_not_found(exception)
        render json: { error: exception.message }, status: :not_found
      end

      def render_unprocessable_content(exception)
        render json: { error: exception.record.errors.full_messages }, status: :unprocessable_content
      end

      def render_bad_request(exception)
        render json: { error: exception.message }, status: :bad_request
      end

      def render_internal_error(exception)
        Rails.logger.error("[#{exception.class}] #{exception.message}\n#{exception.backtrace&.first(10)&.join("\n")}")
        render json: { error: "Internal server error" }, status: :internal_server_error
      end
    end
  end
end
