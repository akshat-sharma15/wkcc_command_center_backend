require "rails_helper"

RSpec.describe HubLoadService do
  it "projects inventory + inbound before cutoff - outbound before cutoff" do
    corridor = build_corridor(expected_arrival_at: 1.hour.from_now)
    hub = corridor[:destination]
    order = create(:order, total_weight: 300, package_count: 1)
    create(:package, location: hub, order: order, status: "pending") # 300 kg inventory
    outbound = create(:trip, vehicle: create(:vehicle, fleet_monitoring_poc: true), origin_hub: hub, destination_hub: corridor[:origin], status: "scheduled", departure_at: 30.minutes.from_now)
    create(:package, trip: outbound, order: create(:order, total_weight: 40, package_count: 1), location: hub, status: "received")

    load = described_class.new(hub, cutoff: 3.hours.from_now).as_json

    expect(load[:inventory_kg]).to eq(340.0) # the outbound package is still at the hub
    expect(load[:inbound_load_kg]).to eq(100.0) # corridor trip carries 2 x 50 kg
    expect(load[:outbound_load_kg]).to eq(40.0)
    expect(load[:projected_load_kg]).to eq(400.0)
    expect(load[:projected_utilization_pct]).to eq(80.0)
    expect(load[:congestion_risk]).to eq("medium")
    expect(load[:inbound_vehicle_count]).to eq(1)
  end

  it "excludes inbound arriving after the cutoff and reports missing capacity" do
    corridor = build_corridor(expected_arrival_at: 6.hours.from_now)
    hub = corridor[:destination]
    hub.update!(load_capacity_kg: nil)

    load = described_class.new(hub, cutoff: 10.minutes.from_now).as_json
    expect(load[:inbound_before_cutoff]).to be_empty
    expect(load[:projected_utilization_pct]).to be_nil
    expect(load[:unavailable]).to eq("hub_capacity_not_configured")
  end
end
