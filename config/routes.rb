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
