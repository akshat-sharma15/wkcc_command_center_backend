require "rails_helper"

RSpec.describe VehicleOperationEvent, type: :model do
  it "is valid with a vehicle, event_type, and occurred_at" do
    expect(build(:vehicle_operation_event)).to be_valid
  end

  it "requires a vehicle" do
    expect(build(:vehicle_operation_event, vehicle: nil)).not_to be_valid
  end

  it "allows a nil trip" do
    expect(build(:vehicle_operation_event, trip: nil)).to be_valid
  end

  it "requires an event_type" do
    expect(build(:vehicle_operation_event, event_type: nil)).not_to be_valid
  end

  it "requires occurred_at" do
    expect(build(:vehicle_operation_event, occurred_at: nil)).not_to be_valid
  end

  it "associates an optional trip when present" do
    trip = create(:trip)
    event = create(:vehicle_operation_event, vehicle: trip.vehicle, trip: trip)

    expect(event.trip).to eq(trip)
  end

  it "stores jsonb metadata" do
    event = create(:vehicle_operation_event, metadata: { "reason" => "engine overheating" })
    expect(event.reload.metadata).to eq("reason" => "engine overheating")
  end
end
