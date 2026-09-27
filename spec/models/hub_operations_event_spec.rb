require "rails_helper"

RSpec.describe HubOperationsEvent, type: :model do
  it "is valid with a hub, event_type, and occurred_at" do
    expect(build(:hub_operations_event)).to be_valid
  end

  it "requires a hub" do
    expect(build(:hub_operations_event, hub: nil)).not_to be_valid
  end

  it "allows nil vehicle, trip, and package" do
    event = build(:hub_operations_event, vehicle: nil, trip: nil, package: nil)
    expect(event).to be_valid
  end

  it "requires an event_type" do
    expect(build(:hub_operations_event, event_type: nil)).not_to be_valid
  end

  it "requires occurred_at" do
    expect(build(:hub_operations_event, occurred_at: nil)).not_to be_valid
  end

  it "associates an optional vehicle, trip, and package when present" do
    hub = create(:hub)
    vehicle = create(:vehicle, hub: hub)
    trip = create(:trip, vehicle: vehicle, destination_hub: hub)
    package = create(:package, location: hub, trip: trip)

    event = create(:hub_operations_event, hub: hub, vehicle: vehicle, trip: trip, package: package,
      event_type: "SCANNED", dock_reference: "D1", bay_reference: "B2")

    expect(event.vehicle).to eq(vehicle)
    expect(event.trip).to eq(trip)
    expect(event.package).to eq(package)
    expect(event.dock_reference).to eq("D1")
    expect(event.bay_reference).to eq("B2")
  end
end
