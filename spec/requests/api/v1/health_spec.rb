require "rails_helper"

RSpec.describe "Api::V1::Health", type: :request do
  describe "GET /api/v1/health" do
    it "is reachable without authentication and confirms both domain databases plus Sidekiq are wired" do
      expect { get "/api/v1/health" }.to change(HealthCheckJob.jobs, :size).by(1)

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["status"]).to eq("ok")
      expect(body["operations_db"]).to eq("ok")
      expect(body["command_center_db"]).to eq("ok")
      expect(body["sidekiq_job_enqueued"]).to eq(true)
    end
  end
end
