# Base class for background jobs. Uses Sidekiq::Job directly rather than
# ActiveJob (ActiveJob isn't loaded — see config/application.rb) so jobs have
# full access to Sidekiq-specific features (perform_in, retry policies, etc.)
# without going through an adapter layer.
class ApplicationJob
  include Sidekiq::Job
end
