module Api
  module V1
    # Unauthenticated. Touches both domain databases with a trivial SELECT 1
    # and enqueues a Sidekiq job, so a single request proves Postgres
    # multi-db wiring and Sidekiq/Redis wiring are alive together on every
    # dev boot (see Stage 1 verification in ARCHITECTURE.md).
    class HealthController < ApplicationController
      def show
        operations_ok = OperationsRecord.connection.select_value("SELECT 1") == 1
        command_center_ok = CommandCenterRecord.connection.select_value("SELECT 1") == 1
        HealthCheckJob.perform_async(Time.current.iso8601)

        render json: {
          status: "ok",
          operations_db: operations_ok ? "ok" : "unreachable",
          command_center_db: command_center_ok ? "ok" : "unreachable",
          sidekiq_job_enqueued: true
        }
      end
    end
  end
end
