require "rails_helper"

RSpec.describe Alertable do
  describe ".alertable_group_key" do
    it "resolves each alertable model's registry key" do
      expect(Vehicle.alertable_group_key).to eq("vehicles")
      expect(Hub.alertable_group_key).to eq("hubs")
      expect(Package.alertable_group_key).to eq("packages")
      expect(PaymentDue.alertable_group_key).to eq("payments")
      expect(WorkforceMember.alertable_group_key).to eq("workforce")
    end
  end

  describe "after_commit enqueues AlertEvaluationJob" do
    it "enqueues when an alertable field changes and allow_alerts is true" do
      vehicle = create(:vehicle, allow_alerts: true, alertable_fields: %w[status])

      expect { vehicle.update!(status: "maintenance") }
        .to change(AlertEvaluationJob.jobs, :size).by(1)
      expect(AlertEvaluationJob.jobs.last["args"]).to eq([ "vehicles", vehicle.id, [ "status" ] ])
    end

    it "does not enqueue when allow_alerts is false" do
      vehicle = create(:vehicle, allow_alerts: false, alertable_fields: %w[status])

      expect { vehicle.update!(status: "maintenance") }
        .not_to change(AlertEvaluationJob.jobs, :size)
    end

    it "does not enqueue when the changed field is not in alertable_fields" do
      vehicle = create(:vehicle, allow_alerts: true, alertable_fields: %w[capacity], current_location: "A")

      expect { vehicle.update!(current_location: "B") }
        .not_to change(AlertEvaluationJob.jobs, :size)
    end

    it "does not enqueue on a no-op save with nothing changed" do
      vehicle = create(:vehicle, allow_alerts: true, alertable_fields: %w[status])

      expect { vehicle.update!(status: vehicle.status) }
        .not_to change(AlertEvaluationJob.jobs, :size)
    end

    it "enqueues on create when the record is created already allow_alerts + matching state" do
      expect { create(:vehicle, allow_alerts: true, alertable_fields: %w[status], status: "maintenance") }
        .to change(AlertEvaluationJob.jobs, :size).by(1)
    end

    it "passes only the fields that actually changed, not the whole alertable_fields list" do
      vehicle = create(:vehicle, allow_alerts: true, alertable_fields: %w[status capacity], capacity: 1000)

      vehicle.update!(status: "maintenance")

      expect(AlertEvaluationJob.jobs.last["args"]).to eq([ "vehicles", vehicle.id, [ "status" ] ])
    end
  end

  # Not tested here: "a rolled-back transaction never fires after_commit" -
  # that's Rails' own documented after_commit contract (the entire reason
  # this concern uses after_commit instead of after_update), and RSpec's
  # transactional-fixture wrapping makes it awkward to independently prove
  # in-test without exercising unrelated Rails internals.
end
