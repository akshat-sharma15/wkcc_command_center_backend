require "rails_helper"

RSpec.describe HealthCheckJob, type: :job do
  it "runs without error and logs the enqueued timestamp" do
    expect(Rails.logger).to receive(:info).with(/HealthCheckJob.*2026-01-01/)
    described_class.new.perform("2026-01-01T00:00:00Z")
  end
end
