# Proof-of-life job for Stage 1: confirms Sidekiq/Redis wiring works
# end-to-end. Enqueued by GET /api/v1/health.
class HealthCheckJob < ApplicationJob
  def perform(enqueued_at)
    Rails.logger.info("[HealthCheckJob] processed, enqueued_at=#{enqueued_at}")
  end
end
