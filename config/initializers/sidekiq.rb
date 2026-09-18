redis_url = ENV.fetch("REDIS_SIDEKIQ_URL") {
  "redis://#{ENV.fetch('REDIS_HOST', 'localhost')}:#{ENV.fetch('REDIS_PORT', 6380)}/#{ENV.fetch('REDIS_SIDEKIQ_DB', 4)}"
}

Sidekiq.configure_server do |config|
  config.redis = { url: redis_url }
end

Sidekiq.configure_client do |config|
  config.redis = { url: redis_url }
end
