require "sidekiq/web"

Rails.application.routes.draw do
  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  get "up" => "rails/health#show", as: :rails_health_check

  namespace :api do
    namespace :v1 do
      get "health" => "health#show"

      resources :vehicles
      resources :trips
      resources :hubs
      resources :warehouses
      resources :packages
      resources :finance, controller: "finance"
      resources :workforce_members
      resources :events

      # Alert-system refactor Phase 2: Alert Builder metadata + AlertRule
      # CRUD. Kebab-case paths as specified for this feature (existing
      # resources above use snake_case, e.g. workforce_members).
      get "alert-resources" => "alert_resources#index"
      get "alert-resources/:group/fields" => "alert_resources#fields"
      get "alert-resources/:group/fields/:field/options" => "alert_resources#field_options"

      get "alert-recipients/roles" => "alert_recipients#roles"
      get "alert-recipients/users" => "alert_recipients#users"

      resources :alert_rules, path: "alert-rules"

      # Slack OAuth connect/status/disconnect (see
      # app/controllers/api/v1/slack_integrations_controller.rb).
      get "integrations/slack" => "slack_integrations#show"
      get "integrations/slack/connect" => "slack_integrations#connect"
      get "integrations/slack/callback" => "slack_integrations#callback"
      delete "integrations/slack/:id" => "slack_integrations#destroy"

      # Alert runtime pipeline: Alert/Notification creation happen in
      # AlertEvaluationJob (triggered by the Alertable concern), not here.
      get "notifications" => "notifications#index"
      get "notifications/unread" => "notifications#unread"
      get "notifications/sse-ticket" => "notifications#sse_ticket"
      get "notifications/stream" => "notifications_stream#stream"
      patch "notifications/:id/read" => "notifications#read"
      get "notifications/:id" => "notifications#show"
    end
  end

  sidekiq_web_username = ENV["SIDEKIQ_WEB_USERNAME"]
  sidekiq_web_password = ENV["SIDEKIQ_WEB_PASSWORD"]

  if sidekiq_web_username.present? && sidekiq_web_password.present?
    Sidekiq::Web.use(Rack::Auth::Basic) do |username, password|
      ActiveSupport::SecurityUtils.secure_compare(username, sidekiq_web_username) &
        ActiveSupport::SecurityUtils.secure_compare(password, sidekiq_web_password)
    end
  end

  mount Sidekiq::Web => "/sidekiq"
end
