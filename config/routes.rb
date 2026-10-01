require "sidekiq/web"

Rails.application.routes.draw do
  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  get "up" => "rails/health#show", as: :rails_health_check

  namespace :api do
    namespace :v1 do
      get "health" => "health#show"

      resources :vehicles
      resources :trips do
        get :eta, on: :member
      end
      resources :hubs do
        get "load" => "hub_loads#show"
        # Same handlers as the fleet-monitoring hub endpoints below (one
        # source of truth: FleetMonitoring::HubVehicleFlow).
        get "vehicles" => "fleet_monitoring/hub_vehicles#index"
        get "vehicle-summary" => "fleet_monitoring/hub_vehicles#summary"
      end
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

      # Alert occurrences: operational history + lifecycle actions. No
      # destroy - alerts are never deleted.
      resources :alerts, only: %i[index show] do
        member do
          post :acknowledge
          post :assign
          post :reassign
          post :escalate
          post :resolve
        end
      end

      # Advanced incidents (IncidentCatalog) and their domain records.
      get "incidents" => "incidents#index"
      post "incidents/:key" => "incidents#create", constraints: { key: /[a-z0-9_.]+/ }
      resources :route_diversions, path: "route-diversions", only: %i[index show create] do
        get :summary, on: :collection
        post :resolve, on: :member
      end
      resources :waybills, only: %i[index show]

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

      # Command Centre AI chatbot (Phase 5) - read-only operational
      # analytics over the approved views/tables only. See
      # Api::V1::AiController / CommandCenter::AiChatService.
      post "ai/chat" => "ai#chat"
      # Chart-scoped chat. Called by Superset (server-to-server, service
      # token) rather than the browser, so the chart's dataset is resolved
      # and access-checked before any context reaches the model.
      post "ai/chart_chat" => "ai#chart_chat"

      # Fleet Monitoring API POC - additive and isolated from the
      # Command Center resources above (they keep serving the full
      # dataset unchanged). Backs the truck_monitoring frontend's map.
      # See app/controllers/api/v1/fleet_monitoring/.
      namespace :fleet_monitoring, path: "fleet-monitoring" do
        get "vehicles" => "vehicles#index"
        get "hubs" => "hubs#index"
        # Map hub focus: only the inbound/outbound vehicles for one hub.
        get "hubs/:code/vehicles" => "hub_vehicles#index"
        get "hubs/:code/vehicle-summary" => "hub_vehicles#summary"
        get "vehicles/:pnr" => "vehicles#show"
        get "waybills" => "waybills#index"
        get "incidents/:id" => "incidents#show"
        get "route-diversions" => "route_diversions#index"
        get "route-diversions/:id" => "route_diversions#show"
        get "packages" => "packages#index"
        get "search" => "search#vehicle"
        get "search/package" => "search#package"
        get "search/waybill" => "search#waybill"
        get "search/suggestions" => "search_suggestions#index"
      end
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
